pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./../../../interfaces/uniswap/IUniswapV2Router02.sol";
import "./../../../interfaces/uniswap/IUniswapV2Pair.sol";
import "./../../../interfaces/uniswap/IUniswapRewards.sol";

import "./../ProfitNotifier.sol";

contract uniswapLPStrategy is ProfitNotifier {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public vault;
    address public governance;
    address public agent;
    
    address public mainAsset;
    address public uniswapRewardToken;
    address public uniswapRewardPool;
    address public lpToken0;
    address public lpToken1;

    mapping(address => address[]) routes;

    constructor(
        address _vault,
        address _mainAsset,
        address _uniRewardToken,
        address _uniRewardPool,
        address _agent
        ) {
        vault = _vault;
        governance = msg.sender;
        agent = _agent;

        mainAsset = _mainAsset;
        uniswapRewardToken = _uniRewardToken;
        uniswapRewardPool = _uniRewardPool;

        lpToken0 = IUniswapV2Pair(mainAsset).token0();
        lpToken1 = IUniswapV2Pair(mainAsset).token1();

        routes[lpToken0] = [uniswapRewardToken, weth, lpToken0];
        routes[lpToken1] = [uniswapRewardToken, lpToken1];
    }

    function setRewardForwarder(address _new) external {
        require(msg.sender == governance, '!governance');
        feeRewardForwarder = _new;
    }

    function setProfitSharingDenominator(uint256 _new) external {
        require(msg.sender == governance, '!governance');
        profitSharingDenominator = _new;
    }

    function setGovernance(address _gov) external {
        require(msg.sender == governance, '!governance');
        governance = _gov;
    }

    function setAgent(address _agent) external {
        require(msg.sender == governance, '!governance');
        agent = _agent;
    }

    function setVault(address _vault) external {
        require(msg.sender == governance, '!governance');
        vault = _vault;
    }

    function setRoute(address _token, address[] memory route) external {
        require(msg.sender == governance, '!governance');
        routes[_token] = route;
    }

    function underlyingBalanceStaked() public view returns(uint256){
        return IUniswapRewards(uniswapRewardPool).balanceOf(address(this));
    }

    function underlyingBalance() public view returns(uint256){
        return IERC20(mainAsset).balanceOf(address(this)).add(underlyingBalanceStaked());
    }

    function _withdrawStrategy(uint256 _amount) internal returns(uint256) {
        uint256 _before = IERC20(mainAsset).balanceOf(address(this));
        IUniswapRewards(uniswapRewardPool).withdraw(_amount);
        return IERC20(mainAsset).balanceOf(address(this)).sub(_before);
    }

    function _withdrawStrategyAll() internal {
        IUniswapRewards(uniswapRewardPool).exit();
    }

    function withdraw(uint256 _amount) public {
        require(msg.sender == vault || msg.sender == governance, '!governance');
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_amount > _balance){
            _amount = _withdrawStrategy(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        require(vault != address(0), 'burning funds');
        IERC20(mainAsset).safeTransfer(vault, _amount);
    }

    function liquidate() public {
        require(msg.sender == vault || msg.sender == governance, '!governance');
        // _harvestProfits();
        _withdrawStrategyAll();

        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        require(vault != address(0), 'burning funds');
        IERC20(mainAsset).safeTransfer(vault, _balance);
    }

    function deposit() public {
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_balance > 0){
            IERC20(mainAsset).safeApprove(uniswapRewardPool, 0);
            IERC20(mainAsset).safeApprove(uniswapRewardPool, _balance);
            IUniswapRewards(uniswapRewardPool).stake(_balance);
        }
    }

    function _harvestProfits() internal {
        uint256 _before = IERC20(mainAsset).balanceOf(address(this));
        uint256 _uniBalBefore = IERC20(uniswapRewardToken).balanceOf(address(this));
        IUniswapRewards(uniswapRewardPool).getReward();
        uint256 _uniBalAfter = IERC20(uniswapRewardToken).balanceOf(address(this));
        if(_uniBalAfter > 0){
            notifyProfit(_uniBalBefore, _uniBalAfter, uniswapRewardToken);

            // Swap to lpTokens, then provide liquidity in exchange for mainAsset
            uint256 _remainingUni = IERC20(uniswapRewardToken).balanceOf(address(this));
            if(_remainingUni > 0){
                IERC20(uniswapRewardToken).safeApprove(uniswapRouter, 0);
                IERC20(uniswapRewardToken).safeApprove(uniswapRouter, _remainingUni);

                IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(_remainingUni.div(2), uint256(0), routes[lpToken0], address(this), block.timestamp.add(1800));
                _remainingUni = IERC20(uniswapRewardToken).balanceOf(address(this));
                IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(_remainingUni, uint256(0), routes[lpToken1], address(this), block.timestamp.add(1800));

                uint256 _token0bal = IERC20(lpToken0).balanceOf(address(this));
                uint256 _token1bal = IERC20(lpToken1).balanceOf(address(this));

                IERC20(lpToken0).safeApprove(uniswapRouter, 0);
                IERC20(lpToken0).safeApprove(uniswapRouter, _token0bal);
                IERC20(lpToken1).safeApprove(uniswapRouter, 0);
                IERC20(lpToken1).safeApprove(uniswapRouter, _token1bal);

                IUniswapV2Router02(uniswapRouter).addLiquidity(lpToken0, lpToken1, _token0bal, _token1bal, 1, 1, address(this), block.timestamp.add(1800));
            }
        }
    }

    function harvestProfits() public {
        require(msg.sender == agent || msg.sender == governance, '!governance');
        _harvestProfits();
        deposit();
    }
}
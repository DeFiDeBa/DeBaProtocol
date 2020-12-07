pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../interfaces/dforce/Rewards.sol";
import "../../../interfaces/dforce/Token.sol";
// import "../../../interfaces/1inch/IOneSplitAudit.sol";
import "./../../../interfaces/uniswap/IUniswapV2Router02.sol";

import "./../ProfitNotifier.sol";

contract DForceStrategy is ProfitNotifier {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant dForce = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0);
    address public constant uniswap = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public vault;
    address public governance;
    address public mainAsset;
    address public dAsset;
    address public dForceRewards;
    address public agent;

    constructor(address _mainAsset, address _dAsset, address _dRewards, address _agent) {
        governance = msg.sender;
        vault = msg.sender;
        mainAsset = _mainAsset;
        dAsset = _dAsset;
        dForceRewards = _dRewards;
        agent = _agent;
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

    function deposit() public {
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_balance > 0) {
            IERC20(mainAsset).safeApprove(dAsset, 0);
            IERC20(mainAsset).safeApprove(dAsset, _balance);
            dERC20(dAsset).mint(address(this), _balance);
        }

        uint256 _dAssetBalance = IERC20(dAsset).balanceOf(address(this));
        if(_dAssetBalance > 0) {
            IERC20(dAsset).safeApprove(dForceRewards, 0);
            IERC20(dAsset).safeApprove(dForceRewards, _dAssetBalance);
            dRewards(dForceRewards).stake(_dAssetBalance);
        }
    }

    function _withdrawFromStrategy(uint256 _amount) internal returns(uint256){
        uint256 _dValue = _amount.mul(1e18).div(dERC20(dAsset).getExchangeRate());
        uint256 _b = IERC20(dAsset).balanceOf(address(this));
        dRewards(dForceRewards).withdraw(_dValue);
        uint256 _a = IERC20(dAsset).balanceOf(address(this));
        uint256 _withdrew = _a.sub(_b);
        _b = IERC20(mainAsset).balanceOf(address(this));
        dERC20(dAsset).redeem(address(this), _withdrew);
        _a = IERC20(mainAsset).balanceOf(address(this));
        _withdrew = _a.sub(_b);
        return _withdrew;
    }

    function _withdrawAllFromStrategy() internal {
        dRewards(dForceRewards).exit();
        uint256 _dAssetBalance = IERC20(dAsset).balanceOf(address(this));
        if(_dAssetBalance > 0) {
            dERC20(dAsset).redeem(address(this), _dAssetBalance);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault || msg.sender == governance, '!governance');
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_balance < _amount){
            _amount = _withdrawFromStrategy(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        // FEES

        require(vault != address(0), 'burning funds');
        IERC20(mainAsset).safeTransfer(vault, _amount);
    }

    function liquidate() external {
        require(msg.sender == vault || msg.sender == governance, '!governance');
        // _harvestProfits();
        _withdrawAllFromStrategy();

        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        require(vault != address(0), 'burning funds');
        IERC20(mainAsset).safeTransfer(vault, _balance);
    }

    function _harvestProfits() internal {
        dRewards(dForceRewards).getReward();
        uint256 _dfBalance = IERC20(dForce).balanceOf(address(this));
        if (_dfBalance > 0) {
            IERC20(dForce).safeApprove(uniswap, 0);
            IERC20(dForce).safeApprove(uniswap, _dfBalance);

            address[] memory path = new address[](3);
            path[0] = dForce;
            path[1] = weth;
            path[2] = mainAsset;

            IUniswapV2Router02(uniswap).swapExactTokensForTokens(_dfBalance, uint256(0), path, address(this), block.timestamp.add(1800));
        }
    }

    function harvestProfits() public {
        require(msg.sender == agent || msg.sender == governance, '!governance');
        uint256 _b = IERC20(mainAsset).balanceOf(address(this));
        _harvestProfits();
        uint256 _a = IERC20(mainAsset).balanceOf(address(this));

        // DO FEES WITH _profit
        notifyProfit(_b, _a, mainAsset);
        deposit();
    }

    function mainAssetBalance() public view returns(uint256) {
        return IERC20(mainAsset).balanceOf(address(this));
    }

    function dAssetUnderlyingBalance() public view returns(uint256) {
        return dERC20(dAsset).getTokenBalance(address(this));
    }

    function dRewardsBalance() public view returns(uint256) {
        return (dRewards(dForceRewards).balanceOf(address(this))).mul(dERC20(dAsset).getExchangeRate()).div(1e18);
    }

    function underlyingBalance() public view returns(uint256) {
        return mainAssetBalance().add(dAssetUnderlyingBalance()).add(dRewardsBalance());
    }
}
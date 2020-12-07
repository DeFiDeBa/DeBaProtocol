pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../../interfaces/dforce/Rewards.sol";
import "../../../interfaces/dforce/Token.sol";
// import "../../../interfaces/1inch/IOneSplitAudit.sol";
import "./../../../interfaces/uniswap/IUniswapV2Router02.sol";

import "./../../../interfaces/curve/Gauge.sol";
import "./../../../interfaces/curve/Mintr.sol";
import "./../../../interfaces/curve/Curve.sol";

import "./../../../interfaces/deba/IVault.sol";

contract renBTCCRVStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant curverenPool = address(0x93054188d876f558f4a66B2EF1d97d16eDf0895B);
    address public constant mainAsset = address(0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D); // renBTC
    address public constant wBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public constant curveLPToken = address(0x49849C98ae39Fff122806C06791Fa73784FB3675); //renBTC-wBTC CRV LP token

    address public vault;
    address public governance;
    address public agent;
    address public crvlpVault;

    constructor(address _vault, address _crvvault, address _agent) {
        vault = _vault;
        governance = msg.sender;
        crvlpVault = _crvvault;
        agent = _agent;
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

    function setLPVault(address _vault) external {
        require(msg.sender == governance, '!governance');
        crvlpVault = _vault;
    }

    function lpTokenBalanceChildVault() public view returns(uint256){
        return (IDebaVault(crvlpVault).getFullSharePrice()).mul(IERC20(crvlpVault).balanceOf(address(this))).div(1e18);
    }

    function underlyingInChildVault() public view returns(uint256){
        return (ICurveFi(curverenPool).get_virtual_price()).mul(lpTokenBalanceChildVault()).div(1e18).div(1e10); // Decimal to 8 => wBTC/renBTC
    }

    function underlyingBalance() public view returns(uint256){
        return IERC20(mainAsset).balanceOf(address(this)).add(underlyingInChildVault());
    }

    function _withdrawStrategy(uint256 _amount) internal returns(uint256) {
        uint256 _before = IERC20(mainAsset).balanceOf(address(this));
        uint256 _beforelp = IERC20(curveLPToken).balanceOf(address(this));

        uint256 _lpTokenToWithdraw = (_amount.mul(1e18)).div(ICurveFi(curverenPool).get_virtual_price());
        uint256 _crvLPVaultSharesToWithdraw = _lpTokenToWithdraw.mul(1e18).mul(1e10).div(IDebaVault(crvlpVault).getFullSharePrice());
        IDebaVault(crvlpVault).withdraw(_crvLPVaultSharesToWithdraw);

        uint256 _lpWithdrawn = IERC20(curveLPToken).balanceOf(address(this)).sub(_beforelp);
        if(_lpWithdrawn > 0){
            uint256 _otherAssetBefore = IERC20(wBTC).balanceOf(address(this));
            IERC20(curveLPToken).safeApprove(curverenPool, 0);
            IERC20(curveLPToken).safeApprove(curverenPool, _lpWithdrawn);
            ICurveFi(curverenPool).remove_liquidity(_lpWithdrawn, [uint256(0), uint256(0)]);

            uint256 _otherWithdrawn = (IERC20(wBTC).balanceOf(address(this))).sub(_otherAssetBefore);
            if(_otherWithdrawn > 0){
                IERC20(wBTC).safeApprove(curverenPool, 0);
                IERC20(wBTC).safeApprove(curverenPool, _otherWithdrawn);
                ICurveFi(curverenPool).exchange(1, 0, _otherWithdrawn, 0);
            }
        }
        return (IERC20(mainAsset).balanceOf(address(this))).sub(_before);
    }

    function _withdrawStrategyAll() internal {
        IDebaVault(crvlpVault).withdrawAll();
        uint256 _lBal = IERC20(curveLPToken).balanceOf(address(this));
        if(_lBal > 0){
            IERC20(curveLPToken).safeApprove(curverenPool, 0);
            IERC20(curveLPToken).safeApprove(curverenPool, _lBal);
            ICurveFi(curverenPool).remove_liquidity(_lBal, [uint256(0), uint256(0)]);

            uint256 _garbage = IERC20(wBTC).balanceOf(address(this));
            if(_garbage > 0){
                IERC20(wBTC).safeApprove(curverenPool, 0);
                IERC20(wBTC).safeApprove(curverenPool, _garbage);
                ICurveFi(curverenPool).exchange(1, 0, _garbage, 0);
            }
        }
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
        _withdrawStrategyAll();

        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        require(vault != address(0), 'burning funds');
        IERC20(mainAsset).safeTransfer(vault, _balance);   
    }

    function deposit() public {
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_balance > 0){
            IERC20(mainAsset).safeApprove(curverenPool, 0);
            IERC20(mainAsset).safeApprove(curverenPool, _balance);
            ICurveFi(curverenPool).add_liquidity([_balance, uint256(0)], 0); // Supply wBTC
        }

        uint256 _lpTokenBalance = IERC20(curveLPToken).balanceOf(address(this));
        if(_lpTokenBalance > 0){
            IERC20(curveLPToken).safeApprove(crvlpVault, 0);
            IERC20(curveLPToken).safeApprove(crvlpVault, _lpTokenBalance);
            IDebaVault(crvlpVault).deposit(_lpTokenBalance);
        }
    }
}
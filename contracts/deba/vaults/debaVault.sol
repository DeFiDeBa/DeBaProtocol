// SPDX-License_Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../utils/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./../../../interfaces/deba/IStrategy.sol";

contract DebaVault is ERC20 {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    address public mainAsset;

    address public governance;
    address public strategy;

    uint256 public bufferMin = 9500;
    uint256 public constant bufferMax = 10000;

    mapping(address => uint256) arbProtection;
    mapping(address => uint256) originArbProtection;
    mapping(address => bool) arbProtectionWhitelist;
    bool public locked = false;
    bool public depositLocked = false;

    constructor(address _mainAsset) ERC20(
        string(abi.encodePacked("DeBa ", ERC20(_mainAsset).name())),
        string(abi.encodePacked("d", ERC20(_mainAsset).symbol())),
        uint8(ERC20(_mainAsset).decimals())
    ) {
        mainAsset = _mainAsset;
        governance = msg.sender;
        strategy = msg.sender;
    }

    function setGovernance(address _gov) external {
        require(msg.sender == governance, '!governance');
        governance = _gov;
    }

    function whitelistArb(address _wht) external {
        require(msg.sender == governance, '!governance');
        arbProtectionWhitelist[_wht] = true;
    }

    function setStrategy(address _strategy) external {
        require(msg.sender == governance, '!governance');
        strategy = _strategy;
    }

    function setBuffer(uint256 _buf) external {
        require(msg.sender == governance, '!governance');
        bufferMin = _buf;
    }

    function totalBalance() public view returns (uint256) {
        return IERC20(mainAsset).balanceOf(address(this)).add(IStrategy(strategy).underlyingBalance());
    }

    function mainAssetAvailable() public view returns(uint256) {
        return IERC20(mainAsset).balanceOf(address(this)).mul(bufferMin).div(bufferMax);
    }

    function _withdrawFromStrategy(uint256 _amount) internal returns(uint256){
        uint256 _balanceBefore = IERC20(mainAsset).balanceOf(address(this));
        IStrategy(strategy).withdraw(_amount);
        uint256 _balanceAfter = IERC20(mainAsset).balanceOf(address(this));
        return _balanceAfter.sub(_balanceBefore);
    }

    function depositToStrategy() public {
        if(locked){
            require(msg.sender == governance, '!governance');
        }
        uint256 _balance = mainAssetAvailable();
        if (_balance > 0){
            IERC20(mainAsset).safeTransfer(strategy, _balance);
            IStrategy(strategy).deposit();
        }
    }

    function deposit(uint256 _amount) public {
        if(locked){
            require(msg.sender == governance, '!governance');
        }
        if(depositLocked){
            require(msg.sender == governance, '!governance');
        }
        if(arbProtectionWhitelist[msg.sender] == false){
            require(arbProtection[msg.sender] != block.number, 'wait for next block');
            require(originArbProtection[tx.origin] != block.number, 'wait for next block');
        }
        arbProtection[msg.sender] = block.number;
        originArbProtection[tx.origin] = block.number;
        uint256 totalPool = totalBalance();
        uint256 _pB = IERC20(mainAsset).balanceOf(address(this));
        IERC20(mainAsset).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _pA = IERC20(mainAsset).balanceOf(address(this));
        uint256 _diff = _pA.sub(_pB);
        uint256 sharesTBE = 0;
        if(totalSupply() == 0){
            sharesTBE = _diff;
        }else{
            sharesTBE = (_diff.mul(totalSupply()).div(totalPool));
        }
        _mint(msg.sender, sharesTBE);
    }

    function depositAll() external {
        if(locked){
            require(msg.sender == governance, '!governance');
        }
        deposit(IERC20(mainAsset).balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public {
        if(locked){
            require(msg.sender == governance, '!governance');
        }
        if(arbProtectionWhitelist[msg.sender] == false){
            require(arbProtection[msg.sender] != block.number, 'wait for next block');
        }
        require(originArbProtection[tx.origin] != block.number, 'wait for next block');
        arbProtection[msg.sender] = block.number;
        originArbProtection[tx.origin] = block.number;
        uint256 _value = (totalBalance().mul(_shares).div(totalSupply()));
        _burn(msg.sender, _shares);
        uint256 _balance = IERC20(mainAsset).balanceOf(address(this));
        if(_value > _balance){
            uint256 _diff = _value.sub(_balance);
            _withdrawFromStrategy(_diff);
            uint256 _poolAfter = IERC20(mainAsset).balanceOf(address(this));
            uint256 _secondDiff = _poolAfter.sub(_balance);
            if(_secondDiff < _diff){
                _value = _balance.add(_secondDiff);
            }
        }
        IERC20(mainAsset).safeTransfer(msg.sender, _value);
    }

    function withdrawAll() external {
        if(locked){
            require(msg.sender == governance, '!governance');
        }
        withdraw(balanceOf(msg.sender));
    }

    function getFullSharePrice() public view returns (uint256){
        if(totalSupply() == 0){
            return 0;
        }else{
            return totalBalance().mul(uint256(10**decimals())).div(totalSupply());
        }
    }

    function lockVault() external {
        require(msg.sender == governance, '!governance');
        locked = true;
    }

    function unlockVault() external {
        require(msg.sender == governance, '!governance');
        locked = false;
    }

    function lockDeposits() external {
        require(msg.sender == governance, '!governance');
        depositLocked = true;
    }

    function unlockDeposits() external {
        require(msg.sender == governance, '!governance');
        depositLocked = false;
    }
}
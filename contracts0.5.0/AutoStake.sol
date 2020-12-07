pragma solidity 0.5.16;

import "./../../interfaces/deba/IRewardPool.sol";

contract AutoStake {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  IRewardPool public rewardPool;
  IERC20 public lpToken;
  uint256 public unit = 1e18;
  uint256 public valuePerShare = unit;
  uint256 public totalShares = 0;
  uint256 public totalValue = 0;
  mapping(address => uint256) public share;

  mapping (address => bool) smartContractStakers;

  event Staked(address indexed user, uint256 amount, uint256 sharesIssued, uint256 oldShareVaule, uint256 newShareValue, uint256 balanceOf);
  event Withdrawn(address indexed user, uint256 total);

  event SmartContractRecorded(address indexed smartContractAddress, address indexed smartContractInitiator);

  constructor(address pool, address token) public {
    rewardPool = IRewardPool(pool);
    lpToken = IERC20(token);
  }

  /**
    Updates the value of each user's share
    and joins the pool back.
   */
  function refreshAutoStake() external {
    exitRewardPool();
    updateValuePerShare();
    restakeIntoRewardPool();
  }

  /**
    Fn called by the user to stake his funds 
    into the contract.
    
    The contract takes the funds from the reward 
    pool, computes the shares of the user, adds 
    the tokens and joins the pool again.
   */
  function stake(uint256 amount) public {
    exitRewardPool();
    updateValuePerShare();

    if(tx.origin != msg.sender) {
      smartContractStakers[msg.sender] = true;
      emit SmartContractRecorded(msg.sender, tx.origin);
    }

    // now we can issue shares
    lpToken.safeTransferFrom(msg.sender, address(this), amount);
    uint256 sharesToIssue = amount.mul(unit).div(valuePerShare);
    totalShares = totalShares.add(sharesToIssue);
    share[msg.sender] = share[msg.sender].add(sharesToIssue);

    uint256 oldValuePerShare = valuePerShare;

    // Rate needs to be updated here, otherwise the valuePerShare would be incorrect.
    updateValuePerShare();

    emit Staked(msg.sender, amount, sharesToIssue, oldValuePerShare, valuePerShare, balanceOf(msg.sender));
    
    restakeIntoRewardPool();
  }

  /**
    Fn called by the user when requesting 
    his funds from the auto staking contract.

    The contract takes the funds from the reward 
    pool, computes the shares of the user, sends 
    the tokens and joins the pool again.
   */
  function exit() public {
    exitRewardPool();
    updateValuePerShare();

    // now we can transfer funds and burn shares
    uint256 toTransfer = balanceOf(msg.sender);
    lpToken.safeTransfer(msg.sender, toTransfer);
    totalShares = totalShares.sub(share[msg.sender]);
    share[msg.sender] = 0;
    emit Withdrawn(msg.sender, toTransfer);

    // Rate needs to be updated here, otherwise the valuePerShare would be incorrect.
    updateValuePerShare();
    
    restakeIntoRewardPool();
  }

  /**
    Computes the balance of a user his shares 
    and returns an amount in `lpToken`.
   */
  function balanceOf(address who) public view returns(uint256) {
    return valuePerShare.mul(share[who]).div(unit);
  }

  /**
    Updates the value of a share. which is 
    based on the amount of staked `lpToken`.
   */
  function updateValuePerShare() internal {
    if (totalShares == 0) {
      totalValue = 0;
      valuePerShare = unit;
    } else {
      totalValue = lpToken.balanceOf(address(this));
      valuePerShare = totalValue.mul(unit).div(totalShares);
    }
  }

  /**
    Exit and do accounting first.
   */
  function exitRewardPool() internal {
    if(rewardPool.balanceOf(address(this)) != 0){
      
      rewardPool.exit();
    }
  }

  /**
    Stake back to the reward pool.
  */
  function restakeIntoRewardPool() internal {
    if(lpToken.balanceOf(address(this)) != 0){
      lpToken.safeApprove(address(rewardPool), 0);
      lpToken.safeApprove(address(rewardPool), lpToken.balanceOf(address(this)));
      rewardPool.stake(lpToken.balanceOf(address(this)));
    }
  }

}

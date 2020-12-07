pragma solidity 0.7.0;

interface IRewardPool {
    function totalSupply() external view returns (uint256);
    function getReward() external;
    function exit() external;
    function withdraw(uint256) external;
    function stake(uint256) external;
    function earned(address) external view returns(uint256);
    function rewardPerToken() external view returns(uint256);
    function getFullSharePrice() external view returns(uint256);
    function balanceOf(address) external view returns(uint256);

    function notifyRewardAmount(uint256) external;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardDenied(address indexed user, uint256 reward);
}
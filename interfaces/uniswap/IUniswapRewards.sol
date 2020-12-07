pragma solidity 0.7.0;

interface IUniswapRewards {
    function withdraw(uint) external;
    function getReward() external;
    function stake(uint) external;
    function balanceOf(address) external view returns (uint);
    function earned(address account) external view returns (uint256);
    function exit() external;
}

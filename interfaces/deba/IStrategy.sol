pragma solidity ^0.7.0;

interface IStrategy {

    function setRewardForwarder(address) external;

    function setProfitSharingDenominator(uint256) external;

    function setGovernance(address) external;

    function setAgent(address) external;

    function setVault(address) external;

    function underlyingBalance() external view returns(uint256);

    function withdraw(uint256) external;

    function liquidate() external;

    function deposit() external;

    function harvestProfits() external;
}
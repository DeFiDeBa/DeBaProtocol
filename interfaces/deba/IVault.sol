pragma solidity ^0.7.0;

interface IDebaVault {
    function totalBalance() external view returns(uint256);

    function mainAsset() external view returns(address);

    function mainAssetAvailable() external view returns(uint256);

    function whitelistArb(address) external;

    function deposit(uint256) external;

    function depositAll() external;
    
    function withdraw(uint256) external;

    function withdrawAll() external;

    function depositToStrategy() external;

    function getFullSharePrice() external view returns(uint256);
}
pragma solidity 0.5.17;

interface IXOption {
    function expiryBlockHeight() external view returns (uint256);
}
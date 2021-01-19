pragma solidity 0.5.17;

import "./IXPool.sol";

interface IXFactory {
    function newXPool(uint256) external returns (IXPool);
}

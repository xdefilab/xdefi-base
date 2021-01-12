pragma solidity 0.5.17;

import "./IXPool.sol";

interface IXFactory {
    function newXPool() external returns (IXPool);
}

pragma solidity 0.5.17;

import "./XVersion.sol";
import "./XPool.sol";
import "./XConfig.sol";

contract XPoolCreator is XApollo {
    function newXPool() external returns (XPool) {
        return new XPool();
    }
}

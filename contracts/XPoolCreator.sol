pragma solidity 0.5.17;

import "./XVersion.sol";
import "./XPool.sol";

contract XPoolCreator is XApollo {
    function newXPool(address config, address controller)
        external
        returns (XPool)
    {
        return new XPool(config, controller);
    }
}

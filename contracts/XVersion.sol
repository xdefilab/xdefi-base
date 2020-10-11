pragma solidity 0.5.17;

contract XVersion {
    function getVersion() external view returns (bytes32);
}

contract XApollo is XVersion {
    function getVersion() external view returns (bytes32) {
        return bytes32("APOLLO");
    }
}

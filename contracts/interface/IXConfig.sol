pragma solidity 0.5.17;

interface IXConfig {
    function getCore() external view returns (address);

    function getSAFU() external view returns (address);

    function getMaxExitFee() external view returns (uint256);

    function getSafuFee() external view returns (uint256);

    function getSwapProxy() external view returns (address);

    function ethAddress() external pure returns (address);

    function dedupPool(address[] calldata tokens, uint256[] calldata denorms)
        external
        returns (bool exist, bytes32 sig);

    function addPoolSig(bytes32 sig, address pool) external;
}

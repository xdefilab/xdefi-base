pragma solidity 0.5.17;

interface IXConfig {
    function getCore() external view returns (address);

    function getSAFU() external view returns (address);

    function getFarmCreator() external view returns (address);

    function getMaxExitFee() external view returns (uint256);

    function getSafuFee() external view returns (uint256);

    function ethAddress() external pure returns (address);
}

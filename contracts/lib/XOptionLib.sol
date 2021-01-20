pragma solidity 0.5.17;

library XOptionLib {
    function calSwapFee(uint256 blockNumber, uint256 expiryBlockHeight, uint256 base) internal pure returns (uint256) {
        require(blockNumber < expiryBlockHeight, "Error: expired");
        uint256 feeRate = sqrt(expiryBlockHeight - blockNumber);
        uint256 actFee = base * 5 / feeRate;
        uint256 minFee = base * 3 / 1000;
        uint256 swapFee = minFee >= actFee ? minFee : actFee;
        return swapFee;
    }

    function sqrt(uint256 x) internal pure returns(uint) {
        uint256 z = (x + 1 ) / 2;
        uint256 y = x;
        while(z < y){
            y = z;
            z = ( x / z + z ) / 2;
        }
        return y;
    }
}
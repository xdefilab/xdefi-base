pragma solidity 0.5.17;

import "./TToken.sol";

contract TTokenFactory {
    mapping(string => TToken) tokens;

    function get(string calldata name) external view returns (TToken) {
        return tokens[name];
    }

    function build(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address owner
    ) external returns (TToken) {
        tokens[name] = new TToken(name, symbol, decimals, owner);
        return tokens[name];
    }
}

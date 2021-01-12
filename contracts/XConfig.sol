pragma solidity 0.5.17;

contract XConfig {
    address public core;

    modifier onlyCore() {
        require(msg.sender == core, "Not Authorized");
        _;
    }

    constructor() public {
        core = msg.sender;
    }
}

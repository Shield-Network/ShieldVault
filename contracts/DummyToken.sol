// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "./OpenZeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20 {
    constructor(uint256 _initialSupply) ERC20("DummyToken", "DMMY") {
      _mint(msg.sender, _initialSupply);
    }
}

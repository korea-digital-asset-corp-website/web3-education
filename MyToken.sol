// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {
    constructor() ERC20("KODA Test Token", "KODA") {}

    function mint(address user, uint256 value) public returns (bool) {
        _mint(user, value);
        return true;
    }

    function burn(address user, uint256 value) public returns (bool) {
        _burn(user, value);
        return true;
    }
}

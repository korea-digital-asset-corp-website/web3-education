// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Calculator {
    event CalculationResult(
        string operation,
        uint256 operand1,
        uint256 operand2,
        uint256 result
    );

    uint256 result = 0;

    function getResult() public view returns (uint256) {
        return result;
    }

    function add(uint256 a, uint256 b) public returns (uint256) {
        result = a + b;
        emit CalculationResult("addition", a, b, result);
        return result;
    }

    function subtract(uint256 a, uint256 b) public returns (uint256) {
        require(b <= a, "Underflow error");
        result = a - b;
        emit CalculationResult("subtraction", a, b, result);
        return result;
    }

    function multiply(uint256 a, uint256 b) public returns (uint256) {
        result = a * b;
        emit CalculationResult("multiplication", a, b, result);
        return result;
    }

    function divide(uint256 a, uint256 b) public returns (uint256) {
        require(b != 0, "Division by zero");
        result = a / b;
        emit CalculationResult("division", a, b, result);
        return result;
    }

    function modulus(uint256 a, uint256 b) public returns (uint256) {
        require(b != 0, "Modulus by zero");
        result = a % b;
        emit CalculationResult("modulus", a, b, result);
        return result;
    }

    function initializeResult() public returns (uint256) {
        result = 0;
        return result;
    }
}
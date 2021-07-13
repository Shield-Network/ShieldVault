// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "hardhat/console.sol";

import "./OpenZeppelin/contracts/upgradeability/ProxyFactory.sol";
import "./OpenZeppelin/contracts/token/ERC20/IERC20.sol";

import "./ShieldVault.sol";

contract ShieldVaultFactory is ProxyFactory {
  event TokenAdded(string name, address token);
  event VaultCreated(address proxy, address createdBy, address token);

  ShieldVault shieldVault;
  address private owner;

  modifier onlyOwner() {
    require(msg.sender == owner, "not owner");
    _;
  }

  struct Token {
    string name;
    IERC20 token;
  }

  Token[] private tokens;

  address vaultImplementation;

  uint256 vaultIndex;
  address[] vaults;
  mapping(address => uint256[]) addressVaults;
  mapping(uint256 => address) vaultOwner;
  
  constructor(address _owner, address _vaultImplementation) {
    owner = _owner;
    vaultImplementation = _vaultImplementation;
  }

  /**
   * @dev Transfer ownership to a new adddress.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    require(_newOwner != address(0), "zero address");
    owner = _newOwner;
  }

  /**
   * @dev Renounce ownership
   */
  function renounceOwnership() public onlyOwner {
      owner = address(0);
  }

  /**
   * @dev Add token
   */
  function addToken(string memory _name, IERC20 _token) public onlyOwner {
    tokens.push(Token(_name, _token));
    emit TokenAdded(_name, address(_token));
  }

  /**
   * @dev Get token
   */
  function getToken(uint _tokenIndex) public view returns (string memory, address) {
    return (tokens[_tokenIndex].name, address(tokens[_tokenIndex].token));
  }

  /**
   * @dev Get the tokens count (tokens.length)
   */
  function getTokenCount() public view returns (uint) {
    return tokens.length;
  }

  /**
   * @dev Get sender vault indexes
   */
  function getVaults(address from) public view returns (uint256[] memory) {
    return addressVaults[from];
  }

  /**
   * @dev Get all vaults
   */
  function getAllVaults() public view returns (address[] memory) {
    return vaults;
  }

  /** 
   * @dev Get specified vault owner
   */
  function getVaultOwner(uint256 _vaultIndex) public view returns (address) {
    return vaultOwner[_vaultIndex];
  }

  /**
   * @dev Get specified vault address
   */
  function getVaultAddress(uint256 _vaultIndex) public view returns (address) {
    return vaults[_vaultIndex];
  }

  /**
   * @dev Set the vault implementation to be cloned
   */
  function setVaultImplementation(address _vaultImplementation) public onlyOwner {
    require(_vaultImplementation != address(0), "zero address");
    vaultImplementation = _vaultImplementation;
  }

  /**
   * @dev Create a new vault - clone vault implementation
   */
  function createVault(uint _tokenIndex, address[] memory _owners, uint _numConfirmationsRequired) public {
    bytes memory payload = abi.encodeWithSelector(shieldVault.initialize.selector, _owners, _numConfirmationsRequired, tokens[_tokenIndex].token, address(this));

    address vault = deployMinimal(vaultImplementation, payload);

    uint256 _vaultIndex = vaultIndex++;
    vaults.push(vault);
    addressVaults[msg.sender].push(_vaultIndex);
    vaultOwner[_vaultIndex] = msg.sender;

    emit VaultCreated(vault, msg.sender, address(tokens[_tokenIndex].token));
  }

  /**
   * @dev Get the owner
   */
  function getOwner() public view returns (address) {
    return owner;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "hardhat/console.sol";

import "./OpenZeppelin/contracts/token/ERC20/IERC20.sol";
import "./OpenZeppelin/contracts/utils/Address.sol";

contract ShieldVault {
    using Address for address;
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event TokenDeposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(
        address indexed owner,
        uint256 indexed txId,
        address indexed to,
        uint256 value,
        bytes data
    );
    event ConfirmTransaction(address indexed owner, uint256 indexed txId);
    event RevokeConfirmation(address indexed owner, uint256 indexed txId);
    event ExecuteTransaction(address indexed owner, uint256 indexed txId);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public numConfirmationsRequired;

    struct Transaction {
        address by;
        address to;
        uint256 value;
        string description;
        bytes data;
        bool executed;
        bool isTokenWithdrawal;
        mapping(address => bool) isConfirmed;
        uint256 numConfirmations;
    }

    uint256 txId;
    mapping(uint256 => Transaction) transactions;

    bool initialized = false;
    IERC20 token;
    uint256 tokenBalance;
    address factory;

    modifier onlyFactory() {
        require(msg.sender == factory, "not factory");
        _;
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint256 _txId) {
        require(_txId >= 0 && _txId < txId, "tx does not exist");
        _;
    }

    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint256 _txId) {
        require(
            !transactions[_txId].isConfirmed[msg.sender],
            "tx already confirmed"
        );
        _;
    }

    constructor() {
        /*empty constructor*/
    }

    /**
     * @dev Initialize state variables
     */
    function initialize(
        address[] memory _owners,
        uint256 _numConfirmationsRequired,
        address _token,
        address _factory
    ) public {
        require(!initialized, "already initialized");
        initialized = true;

        require(_owners.length > 0, "owners required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _owners.length,
            "invalid number of required confirmations"
        );
        require(_token != address(0), "token zero address");
        require(_factory != address(0), "factory zero address");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
        token = IERC20(_token);
        factory = _factory;
    }

    /**
     * @dev Declare a payable fallback function
     *     - it should emit the Deposit event with
     *         - msg.sender
     *         - msg.value
     *         - current amount of ether in the contract (address(this).balance)
     */
    fallback() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /**
     * @dev Add transaction to queue.
     * @param _to The destination address.
     * @param _value The amount to be transfered.
     * @param _description A brief description of this transaction.
     * @param _data An abi encoded signature to be executed after executing the transfer. Only works with for non-token transfers.
     */
    function submitTransaction(
        address _to,
        uint256 _value,
        string memory _description,
        bytes memory _data
    ) public onlyOwner {
        createTransaction(_to, _value, _description, _data, false);
    }

    /**
     * @dev Confirm the specified transaction.
     * @param _txId The transaction id.
     */
    function confirmTransaction(uint256 _txId)
        public
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        notConfirmed(_txId)
    {
        Transaction storage transaction = transactions[_txId];

        require(
            msg.sender != transaction.by,
            "You cannot confirm this transaction."
        );
        require(!transaction.isConfirmed[msg.sender], "tx already confirmed");

        transaction.isConfirmed[msg.sender] = true;
        transaction.numConfirmations += 1;

        emit ConfirmTransaction(msg.sender, _txId);
    }

    /**
     * @dev Execute the specified transaction.
     * @param _txId The transaction id.
     */
    function executeTransaction(uint256 _txId)
        public
        payable
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        Transaction storage transaction = transactions[_txId];

        require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );
        require(!transaction.executed, "tx already executed");

        transaction.executed = true;

        bool success = false;

        if (transaction.isTokenWithdrawal) { // token withdrawal
            success = token.transfer(transaction.to, transaction.value);
            tokenBalance = token.balanceOf(address(this));
        } else { // eth withdrawal
            require(
                address(this).balance >= transaction.value,
                "insufficient balance."
            );
            (success, ) = transaction.to.call{value: transaction.value}(
                transaction.data
            );
        }

        require(success, "tx failed");

        emit ExecuteTransaction(msg.sender, _txId);
    }

    /**
     * @dev Revoke a confirmation in the specified transaction.
     * @param _txId The transaction id.
     */
    function revokeConfirmation(uint256 _txId)
        public
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        Transaction storage transaction = transactions[_txId];

        require(transaction.isConfirmed[msg.sender], "tx not confirmed");

        transaction.isConfirmed[msg.sender] = false;
        transaction.numConfirmations -= 1;

        emit RevokeConfirmation(msg.sender, _txId);
    }

    /**
     * @dev Deposit tokens from token's contract.
     * @param amount The amount to be transfered.
     */
    function deposit(uint256 amount) public {
        require(token.transferFrom(msg.sender, address(this), amount), "tx failed");
        tokenBalance = token.balanceOf(address(this));
        emit TokenDeposit(msg.sender, amount, tokenBalance);
    }

    /**
     * @dev Request a token withdrawal.
     * @param _to The destination address.
     * @param _value The amount to be transfered.
     * @param _description A brief description of this transaction.
     */
    function requestTokenWithdrawal(address _to, uint256 _value, string memory _description)
        public
        onlyOwner
    {
        bytes memory _data = bytes("");
        createTransaction(_to, _value, _description, _data, true);
    }

    /**
     * @dev Create a transaction.
     * @param _to The destination address.
     * @param _value The amount to be transfered.
     * @param _data An abi encoded signature to be executed after executing the transfer. Only works with for non-token transfers.
     * @param _isTokenWithdrawal Specifies if this is a token transaction.
     */
    function createTransaction(
        address _to,
        uint256 _value,
        string memory _description,
        bytes memory _data,
        bool _isTokenWithdrawal
    ) private {
        uint256 _txId = txId;
        Transaction storage transaction = transactions[txId++];
        transaction.by = msg.sender;
        transaction.to = _to;
        transaction.value = _value;
        transaction.description = _description;
        transaction.data = _data;
        transaction.executed = false;
        transaction.isTokenWithdrawal = _isTokenWithdrawal;
        transaction.numConfirmations = 0;

        emit SubmitTransaction(msg.sender, _txId, _to, _value, _data);
    }

    /**
     * @dev Get the owners of this vault
     * @return An array of addresses.
     */
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev Get the number of transactions
     * @return An numeric value;
     */
    function getTransactionCount() public view returns (uint256) {
        return txId;
    }

    /**
     * @dev Get specified transaction information.
     * @param _txId the transaction id.
     */
    function getTransaction(uint256 _txId)
        public
        view
        returns (
            address to,
            uint256 value,
            string memory description,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txId];

        return (
            transaction.to,
            transaction.value,
            transaction.description,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    /**
     * @dev Verify if the specified owner has confirmed the specified transaction.
     * @param _txId The transaction id.
     * @param _owner The owner address.
     */
    function isConfirmed(uint256 _txId, address _owner)
        public
        view
        returns (bool)
    {
        Transaction storage transaction = transactions[_txId];

        return transaction.isConfirmed[_owner];
    }

    /**
     * @dev Get this contract's balance (ETH).
     * @return The balance of this contract (ETH).
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get this contract's token balance.
     * @return This contract's token balance.
     */
    function getTokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}

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

    constructor() {}

    /*
    Exercise
    1. Validate that the _owner is not empty
    2. Validate that _numConfirmationsRequired is greater than 0
    3. Validate that _numConfirmationsRequired is less than or equal to the number of _owners
    4. Set the state variables owners from the input _owners.
        - each owner should not be the zero address
        - validate that the owners are unique using the isOwner mapping
    5. Set the state variable numConfirmationsRequired from the input.
    */
    function initialize(
        address[] memory _owners,
        uint256 _numConfirmationsRequired,
        address _token,
        address _factory
    ) public {
        require(!initialized, "already initialized");
        require(_owners.length > 0, "owners required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _owners.length,
            "invalid number of required confirmations"
        );
        require(address(_token) != address(0), "token zero address");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
        token = IERC20(_token);
        initialized = true;
        factory = _factory;
    }

    /*
    Exercise
    1. Declare a payable fallback function
        - it should emit the Deposit event with
            - msg.sender
            - msg.value
            - current amount of ether in the contract (address(this).balance)
    */
    fallback() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /* Exercise
    1. Complete the onlyOwner modifier defined above.
        - This modifier should require that msg.sender is an owner
    2. Inside submitTransaction, create a new Transaction struct from the inputs
       and append it the transactions array
        - executed should be initialized to false
        - numConfirmations should be initialized to 0
    3. Emit the SubmitTransaction event
        - txId should be the index of the newly created transaction
    */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public onlyOwner {
        createTransaction(_to, _value, _data, false);
    }

    /* Exercise
    1. Complete the modifier txExists
        - it should require that the transaction at txId exists
    2. Complete the modifier notExecuted
        - it should require that the transaction at txId is not yet executed
    3. Complete the modifier notConfirmed
        - it should require that the transaction at txId is not yet
          confirmed by msg.sender
    4. Ensure that the user that created the transaction is not trying to confirm it.
    5. Confirm the transaction
        - update the isConfirmed to true for msg.sender
        - increment numConfirmation by 1
        - emit ConfirmTransaction event for the transaction being confirmed
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

        transaction.isConfirmed[msg.sender] = true;
        transaction.numConfirmations += 1;

        emit ConfirmTransaction(msg.sender, _txId);
    }

    /* Exercise
    1. Execute the transaction
        - it should require that number of confirmations >= numConfirmationsRequired
        - set executed to true
        - execute the transaction using the low level call method
        - require that the transaction executed successfully
        - emit ExecuteTransaction
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
        
        transaction.executed = true;

        bool success = false;

        if(transaction.isTokenWithdrawal) {
          success = token.transfer(transaction.to, transaction.value);
          // bytes memory payload = abi.encodeWithSelector(token.transfer.selector, transaction.to, transaction.value);
          // bytes memory returnedData = address(token).functionCall(payload, "low-level call failed");

          // if(returnedData.length > 0) {
          //   require(abi.decode(returnedData, (bool)), 'operation did not succeed');
          // }
          tokenBalance = token.balanceOf(address(this));
        }
        else {
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

    /* Exercise
    1. Add appropriate modifiers
        - only owner should be able to call this function
        - transaction at _txId must exist
        - transaction at _txId must be executed
    2. Revoke the confirmation
        - require that msg.sender has confirmed the transaction
        - set isConfirmed to false for msg.sender
        - decrement numConfirmations by 1
        - emit RevokeConfirmation
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

    function deposit(uint256 amount) public {
      require(token.transferFrom(msg.sender, address(this), amount), "tx failed");
      tokenBalance = token.balanceOf(address(this));
      emit TokenDeposit(msg.sender, amount, tokenBalance);
    }
    function requestTokenWithdrawal(address _to, uint256 _value) public onlyOwner {
      bytes memory _data = bytes("");
      createTransaction(_to, _value, _data, true);
    }

    function createTransaction(address _to, uint256 _value, bytes memory _data, bool _isTokenWithdrawal) private {
      uint256 _txId = txId;
      Transaction storage transaction = transactions[txId++];
      transaction.by = msg.sender;
      transaction.to = _to;
      transaction.value = _value;
      transaction.data = _data;
      transaction.executed = false;
      transaction.isTokenWithdrawal = _isTokenWithdrawal;
      transaction.numConfirmations = 0;

      emit SubmitTransaction(msg.sender, _txId, _to, _value, _data);
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint256) {
        return txId;
    }

    function getTransaction(uint256 _txId)
        public
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txId];

        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    function isConfirmed(uint256 _txId, address _owner)
        public
        view
        returns (bool)
    {
        Transaction storage transaction = transactions[_txId];

        return transaction.isConfirmed[_owner];
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}

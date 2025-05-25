// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// A flexible multi-signature wallet for secure operations
contract MultiSigWallet is ReentrancyGuard {
    struct Transaction {
        uint256 id;
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
        uint256 timestamp;
        string description;
    }

    struct Proposal {
        uint256 transactionId;
        address proposer;
        uint256 timestamp;
        bool active;
    }

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    mapping(address => bool) public isOwner;
    
    address[] public owners;
    uint256 public required; 
    uint256 public transactionCount;
    uint256 public confirmationTimeout = 7 days; 
    
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequiredChanged(uint256 required);
    event TransactionSubmitted(uint256 indexed transactionId, address indexed proposer);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);
    event TransactionRevoked(uint256 indexed transactionId, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionId);
    event TimeoutChanged(uint256 newTimeout);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier transactionExists(uint256 _transactionId) {
        require(_transactionId < transactionCount, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 _transactionId) {
        require(!transactions[_transactionId].executed, "Transaction already executed");
        _;
    }

    modifier notExpired(uint256 _transactionId) {
        require(
            block.timestamp <= transactions[_transactionId].timestamp + confirmationTimeout,
            "Transaction expired"
        );
        _;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required confirmations");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }
        required = _required;
    }

    
    //  Submit a new transaction proposal
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data,
        string memory _description
    ) public onlyOwner returns (uint256) {
        uint256 transactionId = transactionCount;
        
        transactions[transactionId] = Transaction({
            id: transactionId,
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            confirmations: 0,
            timestamp: block.timestamp,
            description: _description
        });

        transactionCount++;
        emit TransactionSubmitted(transactionId, msg.sender);
        
        // Auto-confirm by proposer
        confirmTransaction(transactionId);
        
        return transactionId;
    }

    
    //  Confirm a transaction
    function confirmTransaction(uint256 _transactionId)
        public
        onlyOwner
        transactionExists(_transactionId)
        notExecuted(_transactionId)
        notExpired(_transactionId)
    {
        require(!confirmations[_transactionId][msg.sender], "Transaction already confirmed");

        confirmations[_transactionId][msg.sender] = true;
        transactions[_transactionId].confirmations++;

        emit TransactionConfirmed(_transactionId, msg.sender);

        // Auto-execute txn if enough confirmations
        if (transactions[_transactionId].confirmations >= required) {
            executeTransaction(_transactionId);
        }
    }

    
    //   Execute a confirmed transaction
    function executeTransaction(uint256 _transactionId)
        public
        nonReentrant
        transactionExists(_transactionId)
        notExecuted(_transactionId)
        notExpired(_transactionId)
    {
        require(
            transactions[_transactionId].confirmations >= required,
            "Insufficient confirmations"
        );

        Transaction storage txn = transactions[_transactionId];
        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(_transactionId);
    }

    
    //   Get transaction details
    function getTransaction(uint256 _transactionId)
        public
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmationCount,
            uint256 timestamp,
            string memory description
        )
    {
        Transaction storage txn = transactions[_transactionId];
        return (
            txn.to,
            txn.value,
            txn.data,
            txn.executed,
            txn.confirmations,
            txn.timestamp,
            txn.description
        );
    }

    
    //  Check if transaction is confirmed by signatories
    function isConfirmed(uint256 _transactionId, address _owner)
        public
        view
        returns (bool)
    {
        return confirmations[_transactionId][_owner];
    }

    
    //  Get list of signatories
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    
    //  Change confirmation timeout (requires multisig)
    function changeTimeout(uint256 _newTimeout) external {
        require(msg.sender == address(this), "Can only be called by multisig");
        confirmationTimeout = _newTimeout;
        emit TimeoutChanged(_newTimeout);
    }

    receive() external payable {}
}

// GNaira
//   ERC20 token with multi-signature governance and compliance features
contract GNaira is ERC20, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    MultiSigWallet public multiSigWallet;
    
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public lastTransactionTime;
    
    uint256 public maxSupply = 1000000000 * 10**18; // 1 billion tokens max
    uint256 public dailyTransferLimit = 1000000 * 10**18; // 1 million tokens daily limit
    uint256 public constant RATE_LIMIT_DURATION = 1 days;
    
    struct PendingOperation {
        uint256 id;
        OperationType opType;
        address target;
        uint256 amount;
        bool executed;
        uint256 confirmations;
        string reason;
    }

    enum OperationType { MINT, BURN, BLACKLIST, UNBLACKLIST }

    mapping(uint256 => PendingOperation) public pendingOperations;
    mapping(uint256 => mapping(address => bool)) public operationConfirmations;
    uint256 public operationCount;
    uint256 public requiredConfirmations;

    event Blacklisted(address indexed account, string reason);
    event Unblacklisted(address indexed account);
    event MultiSigWalletChanged(address indexed oldWallet, address indexed newWallet);
    event OperationProposed(uint256 indexed operationId, OperationType opType, address indexed proposer);
    event OperationConfirmed(uint256 indexed operationId, address indexed confirmer);
    event OperationExecuted(uint256 indexed operationId);
    event EmergencyMint(address indexed to, uint256 amount, string reason);
    event MaxSupplyChanged(uint256 oldSupply, uint256 newSupply);

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Account is blacklisted");
        _;
    }

    modifier onlyMultiSig() {
        require(msg.sender == address(multiSigWallet), "Only multisig can call");
        _;
    }

    modifier validAddress(address account) {
        require(account != address(0), "Invalid address");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address[] memory governors,
        uint256 _requiredConfirmations,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        require(governors.length > 0, "At least one governor required");
        require(_requiredConfirmations > 0 && _requiredConfirmations <= governors.length, 
                "Invalid required confirmations");

        // Deploy multisig wallet
        multiSigWallet = new MultiSigWallet(governors, _requiredConfirmations);
        requiredConfirmations = _requiredConfirmations;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, address(multiSigWallet));
        _grantRole(GOVERNOR_ROLE, address(multiSigWallet));
        
        for (uint256 i = 0; i < governors.length; i++) {
            _grantRole(GOVERNOR_ROLE, governors[i]);
            _grantRole(MINTER_ROLE, governors[i]);
            _grantRole(BURNER_ROLE, governors[i]);
            _grantRole(BLACKLIST_MANAGER_ROLE, governors[i]);
            _grantRole(PAUSER_ROLE, governors[i]);
        }

        // Initial mint
        if (initialSupply > 0) {
            require(initialSupply <= maxSupply, "Initial supply exceeds max supply");
            _mint(address(multiSigWallet), initialSupply);
        }
    }

    // Propose a mint operation (requires multisig confirmation)
    function proposeMint(address to, uint256 amount, string memory reason)
        public
        onlyRole(MINTER_ROLE)
        validAddress(to)
        returns (uint256)
    {
        require(amount > 0, "Amount must be positive");
        require(totalSupply() + amount <= maxSupply, "Would exceed max supply");

        uint256 operationId = operationCount++;
        pendingOperations[operationId] = PendingOperation({
            id: operationId,
            opType: OperationType.MINT,
            target: to,
            amount: amount,
            executed: false,
            confirmations: 0,
            reason: reason
        });

        emit OperationProposed(operationId, OperationType.MINT, msg.sender);
        
        // Auto-confirm by proposer
        confirmOperation(operationId);
        
        return operationId;
    }

    //  Propose a burn operation (requires multisig confirmation)
    function proposeBurn(address from, uint256 amount, string memory reason)
        public
        onlyRole(BURNER_ROLE)
        validAddress(from)
        returns (uint256)
    {
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Insufficient balance to burn");

        uint256 operationId = operationCount++;
        pendingOperations[operationId] = PendingOperation({
            id: operationId,
            opType: OperationType.BURN,
            target: from,
            amount: amount,
            executed: false,
            confirmations: 0,
            reason: reason
        });

        emit OperationProposed(operationId, OperationType.BURN, msg.sender);
        
        // Auto-confirm by proposer
        confirmOperation(operationId);
        
        return operationId;
    }

    
    //  Propose blacklisting an address
    function proposeBlacklist(address account, string memory reason)
        public
        onlyRole(BLACKLIST_MANAGER_ROLE)
        validAddress(account)
        returns (uint256)
    {
        require(!blacklisted[account], "Already blacklisted");

        uint256 operationId = operationCount++;
        pendingOperations[operationId] = PendingOperation({
            id: operationId,
            opType: OperationType.BLACKLIST,
            target: account,
            amount: 0,
            executed: false,
            confirmations: 0,
            reason: reason
        });

        emit OperationProposed(operationId, OperationType.BLACKLIST, msg.sender);
        
        // Auto-confirm by proposer
        confirmOperation(operationId);
        
        return operationId;
    }


    //  Propose removing address from blacklist
    function proposeUnblacklist(address account, string memory reason)
        public
        onlyRole(BLACKLIST_MANAGER_ROLE)
        validAddress(account)
        returns (uint256)
    {
        require(blacklisted[account], "Not blacklisted");

        uint256 operationId = operationCount++;
        pendingOperations[operationId] = PendingOperation({
            id: operationId,
            opType: OperationType.UNBLACKLIST,
            target: account,
            amount: 0,
            executed: false,
            confirmations: 0,
            reason: reason
        });

        emit OperationProposed(operationId, OperationType.UNBLACKLIST, msg.sender);
        
        // Auto-confirm by proposer
        confirmOperation(operationId);
        
        return operationId;
    }

    
    //  Confirm a pending operation
    function confirmOperation(uint256 operationId) public onlyRole(GOVERNOR_ROLE) {
        require(operationId < operationCount, "Operation does not exist");
        require(!pendingOperations[operationId].executed, "Operation already executed");
        require(!operationConfirmations[operationId][msg.sender], "Already confirmed");

        operationConfirmations[operationId][msg.sender] = true;
        pendingOperations[operationId].confirmations++;

        emit OperationConfirmed(operationId, msg.sender);

        // Auto-execute if enough confirmations
        if (pendingOperations[operationId].confirmations >= requiredConfirmations) {
            executeOperation(operationId);
        }
    }

    
    //  Execute a confirmed operation
    function executeOperation(uint256 operationId) public {
        require(operationId < operationCount, "Operation does not exist");
        require(!pendingOperations[operationId].executed, "Operation already executed");
        require(
            pendingOperations[operationId].confirmations >= requiredConfirmations,
            "Insufficient confirmations"
        );

        PendingOperation storage op = pendingOperations[operationId];
        op.executed = true;

        if (op.opType == OperationType.MINT) {
            _mint(op.target, op.amount);
        } else if (op.opType == OperationType.BURN) {
            _burn(op.target, op.amount);
        } else if (op.opType == OperationType.BLACKLIST) {
            blacklisted[op.target] = true;
            emit Blacklisted(op.target, op.reason);
        } else if (op.opType == OperationType.UNBLACKLIST) {
            blacklisted[op.target] = false;
            emit Unblacklisted(op.target);
        }

        emit OperationExecuted(operationId);
    }
  

    
    //  Update max supply (requires multisig)
    function updateMaxSupply(uint256 newMaxSupply) external onlyMultiSig {
        require(newMaxSupply >= totalSupply(), "New max supply too low");
        uint256 oldSupply = maxSupply;
        maxSupply = newMaxSupply;
        emit MaxSupplyChanged(oldSupply, newMaxSupply);
    }


    
    //  Pause token transfers
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }


    //  Unpause token transfers
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    
    // Get pending operation details
    function getPendingOperation(uint256 operationId)
        public
        view
        returns (
            OperationType opType,
            address target,
            uint256 amount,
            bool executed,
            uint256 confirmations,
            string memory reason
        )
    {
        PendingOperation storage op = pendingOperations[operationId];
        return (op.opType, op.target, op.amount, op.executed, op.confirmations, op.reason);
    }

    
    //  Check if operation is confirmed by specific governor
    function isOperationConfirmed(uint256 operationId, address governor)
        public
        view
        returns (bool)
    {
        return operationConfirmations[operationId][governor];
    }

    
    //   Get multisig wallet contract address
    function getMultiSigWallet() public view returns (address) {
        return address(multiSigWallet);
    }

    
    //  Check if address is blacklisted
    function isBlacklisted(address account) public view returns (bool) {
        return blacklisted[account];
    }

    
    //  Get total number of pending operations
    function getPendingOperationsCount() public view returns (uint256) {
        return operationCount;
    }
}
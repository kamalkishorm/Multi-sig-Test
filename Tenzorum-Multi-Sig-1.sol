pragma solidity ^0.4.19;


/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract TenzMultiSig {

    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint required);
    event FirstSignature(address _signer);         // event called when firstSignature of recovery is given.

    /*
     *  Constants
     */
    uint constant public MAX_OWNER_COUNT = 4;
    uint constant public CONSTRUCTOR_FEE = 1 ether;
    uint constant public WINNING_NOMINATOR = 75;         // percentage of funds given to first siganture.
    uint constant public LOSING_NOMINATOR = 25;          // percentage of funds given to second signature.

    /*
     *  Storage
     */
    mapping (uint => Transaction) public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;
    mapping (address => bool) public isGuardian;
    mapping (address => bool) public isOwner;
    mapping (address => uint) public Balances;     // balances of contract plus guardians
    
    address public owner;
    address[] public guardians;
    uint public required;
    uint public transactionCount;
    uint public ownerCount;
    

    struct Transaction {
        address destination;
        uint value;
        address[] signatures;       // Signatures for recoveryTx, has to be true in func param
        bytes data;
        //bytes data;
        bool executed;
        bool recovery;             // is transaction recover yes or no.       
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }

    modifier guardianDoesNotExist(address _newGuardian) {
        require(isGuardian[_newGuardian] = false);
        _;
    }

    modifier guardianExists(address _guardian) {
        require(isGuardian[_guardian] = true);
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner]);
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner]);
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != 0);
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        require(confirmations[transactionId][owner]);
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner]);
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed);
        _;
    }

    modifier notNull(address _address) {
        require(_address != 0);
        _;
    }

    modifier validRequirement(uint guardianCount, uint _required) {
        require(guardianCount <= MAX_OWNER_COUNT
            && _required <= guardianCount
            && _required != 0
            && ownerCount != 0);
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function()
        payable
        public
    {
        if (msg.value > 0)
            Deposit(msg.sender, msg.value);
    }

    
    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _guardians List of initial owners.
    /// @param _required Number of required confirmations.
    function TenzMultiSig (address[] _guardians, uint _required) public payable validRequirement(guardians.length, _required) {
        owner = msg.sender;
        require (msg.value >= CONSTRUCTOR_FEE);
        for (uint i = 0; i < _guardians.length; i++) {
            require(!isGuardian[_guardians[i]] && _guardians[i] != 0);
            isGuardian[_guardians[i]] = true;
        }
        Balances[this] = Balances[this] + msg.value;
        guardians = _guardians;
        required = _required;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param _guardian Address of new guardian.
    function addGuardian(address _guardian) public onlyWallet guardianDoesNotExist(_guardian) notNull(owner) validRequirement(guardians.length + 1, required) {
        isGuardian[_guardian] = true;
        guardians.push(_guardian);
        OwnerAddition(_guardian);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param _guardian Address of guardian.
    function removeGuardian(address _guardian) public onlyWallet guardianExists(_guardian) {
        isGuardian[_guardian] = false;

        for (uint i = 0; i < guardians.length - 1; i++)
            if (guardians[i] == _guardian) {
                guardians[i] = guardians[guardians.length - 1];
                break;
            }
        guardians.length -= 1;
        if (required > guardians.length)
            changeRequirement(guardians.length);
        OwnerRemoval(_guardian);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param _owner Address of owner to be replaced.
    /// @param _newOwner Address of new owner.
    function replaceOwner(address _owner, address _newOwner) public onlyWallet ownerExists(_owner) ownerDoesNotExist(_newOwner) {
        isOwner[_owner] = false;
        isOwner[_newOwner] = true;
        OwnerRemoval(_owner);
        OwnerAddition(_newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required) public onlyWallet validRequirement(guardians.length, _required) {
        required = _required;
        RequirementChange(_required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param _destination Transaction target address.
    /// @param _value Transaction ether value.
    /// @param _data Transaction data payload.
    /// @param _signatures Transaction will be signed by guardians and stored here. 
    /// @param _recovery Is transaction a recovery or not. 
    /// @return Returns transaction ID.
    function submitTransaction(address _destination, uint _value, bytes _data, address[] _signatures, bool _recovery) onlyWallet returns (uint _transactionId) {
        _transactionId = addTransaction(_destination, _value, _data, _signatures, _recovery);
        confirmTransaction(_transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param _transactionId Transaction ID.
    function confirmTransaction(uint _transactionId) public guardianExists(msg.sender) transactionExists(_transactionId) notConfirmed(_transactionId, msg.sender) {
        confirmations[_transactionId][msg.sender] = true;
        Confirmation(msg.sender, _transactionId);
    }
    
    /// @dev Allows an guardian to sign a confirmation for a transaction.
    /// @param _transactionId Transaction ID.
    function signTransaction(uint _transactionId) public guardianExists(_guardian) transactionExists(_transactionId)  {
        address _guardian = msg.sender;
        bool yes;
        Transaction storage txn = transactions[_transactionId];
        require (required > txn.signatures.length && yes == txn.recovery);
        if (required > txn.signatures.length) {
            txn.signatures.length - 1;
        }
        checkSignatures(_transactionId);
        confirmTransaction(_transactionId);
        sendRecoveryFunds(_guardian, _transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param _transactionId Transaction ID.
    function revokeConfirmation(uint _transactionId) public guardianExists(msg.sender) confirmed(_transactionId, msg.sender) notExecuted(_transactionId) {
        confirmations[_transactionId][msg.sender] = false;
        Revocation(msg.sender, _transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param _transactionId Transaction ID.
    function executeTransaction(uint _transactionId) public guardianExists(msg.sender) confirmed(_transactionId, msg.sender) notExecuted(_transactionId) {
        if (isConfirmed(_transactionId)) {
            Transaction storage txn = transactions[_transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                Execution(_transactionId);
            else {
                ExecutionFailure(_transactionId);
                txn.executed = false;
            }
        }
    }
  
    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes data) private returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                d,
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param _transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint _transactionId) public constant returns (bool) {
        uint count = 0;
        for (uint i = 0; i < guardians.length; i++) {
            if (confirmations[_transactionId][guardians[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param _destination Transaction target address.
    /// @param _value Transaction ether value.
    /// @param _data Transaction data payload.
    /// @param _signatures Transaction will be signed by guardians and stored here.
    /// @param _yesNo Transaction is a recovery yes or no.
    /// @return Returns transaction ID.
    function addTransaction(address _destination, uint _value, bytes _data, address[] _signatures, bool _yesNo) internal notNull(_destination) returns (uint transactionId) {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: _destination,
            value: _value,
            signatures: _signatures,
            data: _data,
            executed: false,
            recovery: _yesNo
        });
        transactionCount += 1;
        Submission(transactionId);
    }
    
    /// @dev checks the amount of signatures given to the transaction.
    /// @param _transactionId Transaction ID.
    function checkSignatures(uint _transactionId) internal transactionExists(_transactionId) returns (uint) {
        Transaction storage txn = transactions[_transactionId];
        uint i = 0;
        if (i > txn.signatures.length) {
            return 0;
        } else if (i < txn.signatures.length) {
            return txn.signatures.length;
        }
    }

    /// @dev Sends value of recovery transaction to the guardians who signed, 
    ///      75% for the first to sign and 25% for the second.
    /// @param _guardian Is defined as msg.sender in signTransaction function.
    /// @param _transactionId Transaction ID. 
    function sendRecoveryFunds(address _guardian, uint _transactionId) internal onlyWallet {
        Transaction storage txn = transactions[_transactionId];
        if (_guardian == txn.signatures[1]) {
            Balances[this] -= WINNING_NOMINATOR * txn.value / 100;
            Balances[_guardian] += WINNING_NOMINATOR * txn.value / 100;
            FirstSignature(_guardian);
        } else if (_guardian == txn.signatures[2]) {
            Balances[this] -= LOSING_NOMINATOR * txn.value / 100;
            Balances[_guardian] += LOSING_NOMINATOR * txn.value / 100;
            assert (Balances[_guardian] >= 75 * txn.value / 100 || Balances[_guardian] >= 25 * txn.value / 100);
        }
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param _transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint _transactionId) public constant returns (uint count) {
        for (uint i = 0; i < guardians.length; i++)
            if (confirmations[_transactionId][guardians[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param _pending Include pending transactions.
    /// @param _executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool _pending, bool _executed) public constant returns (uint count) {
        
        for (uint i = 0; i < transactionCount; i++)
            if ( _pending && !transactions[i].executed || _executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getGuardians() public constant returns (address[]) {
        return guardians;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param _transactionId Transaction ID.
    /// @param _guardian Address of confirmations being returned.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint _transactionId, address _guardian) public constant returns (address[] _confirmations) {
        address[] memory confirmationsTemp = new address[](guardians.length);
        uint count = 0;
        uint i;
        for (i = 0; i < guardians.length; i++)
            if (confirmations[_transactionId][guardians[i]]) {
                confirmationsTemp[count] = guardians[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i = 0; i < count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns current signature length of recovery transaction.
    /// @param _transactionId Transaction ID.
    function checkSignatureLength(uint _transactionId) public view transactionExists(_transactionId) returns (uint) {
    Transaction storage txn = transactions[_transactionId];
    return txn.signatures.length;
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param _from Index start position of transaction array.
    /// @param _to Index end position of transaction array.
    /// @param _pending Include pending transactions.
    /// @param _executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint _from, uint _to, bool _pending, bool _executed) public constant returns (uint[] _transactionIds) {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i = 0; i < transactionCount; i++)
            if (   _pending && !transactions[i].executed || _executed && transactions[i].executed) {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](_to - _from);
        for (i = _from; i < _to; i++)
            _transactionIds[i - _from] = transactionIdsTemp[i];
    }
    
}
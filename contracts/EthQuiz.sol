pragma solidity 0.4.15;

// import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";
// import "github.com/Arachnid/solidity-stringutils/strings.sol";
import "./oraclizeAPI.sol";
import "./strings.sol";

contract EthQuiz is usingOraclize {

    using strings for *;

    // the owner of the contract
    address owner = msg.sender;

    // quiz params
    QuizState public currentQuizState = QuizState.setup;

    string private _quizId = "com.ethquiz.edition_1";
    uint private _entryFee = 150000000000000000;
    uint private _adminPercentage = 15;

    string private _answerOutcomeUrl;

    uint[] public winningIndiciesArray;

    uint public rewardPool = 0;
    uint public rewardSplit = 0;
    uint public totalEntries = 0;

    mapping (bytes32 => address) _oracleAnswersMapping; //oraclize queries vs entrant mappings - url, correct answers
    
    // all entries
    mapping (address => Entry) entries; // all quiz entries

    // entries with correct answers
    Entry[] correctEntriesArray; // correct entries only

    // winners after random 50% selection
    mapping (address => uint) winners; // final winning entrants

    uint payoutPeriodStart; 

    enum QuizState {
        setup,
        inProgress,
        paused,
        ended,
        payout,
        refund
    }

    //==================== EVENTS ====================
    event LogFallbackFunctionCalled(address byUser, uint amount);
    event LogNewOraclizeQueryError(string description);
    event LogNewEntry(string qId, address entrant, uint rewardpool, uint totalEnries, uint correctEntries);
    event LogQuizStarted(string qId);
    event LogQuizEnded(string qId);
    event LogPayoutsReady(string qId);
    event LogRefundsEnabled(string qId);
    //---------------------------------------------------

    //==================== ENUMS & STRUCTS ====================
    struct Entry {
        address entrantAddress;
        uint entryFunds;
        string answersString;
        uint oriclizeCost;
    }
    //---------------------------------------------------------

    // fallback function
    function() payable {
        LogFallbackFunctionCalled(msg.sender, msg.value);
    }

    function EthQuiz() {}

    //==================== MODIFIERS ====================
    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }

    modifier onlyState(QuizState expectedState) {
        require(expectedState == currentQuizState);
        _;
    }
    //---------------------------------------------------------

    //==================== HELPER FUNCTIONS ====================
    function getNumCorrectEntries() constant
        returns(uint)
    {
        return correctEntriesArray.length;
    }

    function getNumWinners() constant
        returns(uint)
    {
        uint numCorrectEntries = getNumCorrectEntries();

        uint numWinners = numCorrectEntries;

        if(numCorrectEntries >= 2) {
            if(numCorrectEntries % 2 != 0) {
                // uneven numb of correct entries
                numCorrectEntries --;
            }
            numWinners = numCorrectEntries / 2;
        }

        return numWinners;   
    }

    function getOracleURLGasEstimate() constant
        returns(uint)
    {
        return oraclize_getPrice("URL");
    }

    function getWinningIndiciesLength() constant
        returns(uint)
    {
        return winningIndiciesArray.length;
    }
    //---------------------------------------------------------

    //==================== OWNER FUNCTIONS ====================
    // open quiz for accepting entries
    function startQuiz(string answerOutcomeUrl)
        onlyBy(owner)
        onlyState(QuizState.setup)
        returns(bool)
    {
        _answerOutcomeUrl = answerOutcomeUrl;

        currentQuizState = QuizState.inProgress;

        LogQuizStarted(_quizId);
    }

    function pauseQuiz()
        onlyBy(owner)
        onlyState(QuizState.inProgress)
    {
        currentQuizState = QuizState.paused;
    }

    function resumeQuiz()
        onlyBy(owner)
        onlyState(QuizState.paused)
    {
        currentQuizState = QuizState.inProgress;
    }

    // close all entries to the quiz
    function endQuiz()
        onlyBy(owner)
        onlyState(QuizState.inProgress)
        returns(bool)
    {
        currentQuizState = QuizState.ended;

        uint numWinners = getNumWinners();

        if(numWinners == 0) {
            rewardSplit = rewardPool;
        }
        else {
            rewardSplit = rewardPool / numWinners;
        }

        LogQuizEnded(_quizId);
        
        return true;
    }

    /// winners determined off-chain due to oracle + gass restrictions
    function setWinningIndicies (uint[] winIndexes)
        onlyBy(owner)
        onlyState(QuizState.ended)
    {
        Entry memory winningEntry;

        for(uint i = 0; i < winIndexes.length; i++) {
            // add to winningIndiciesArray
            winningIndiciesArray.push(winIndexes[i]);

            // retrieve full entry
            winningEntry = correctEntriesArray[winIndexes[i]];

            // add rewardsplit to winner
            winners[winningEntry.entrantAddress] += rewardSplit;
        }
    }

    function enablePayouts()
        onlyBy(owner)
        onlyState(QuizState.ended)
    {
        payoutPeriodStart = now;
        currentQuizState = QuizState.payout;
        LogPayoutsReady(_quizId);
    }

    /// refund state can be activated at any point in time
    function enabledRefunds()
        onlyBy(owner)
    {
        currentQuizState = QuizState.refund;

        LogRefundsEnabled(_quizId);
    }
    
    function cashoutUnclaimed()
        onlyBy(owner)
        onlyState(QuizState.payout)
    {
        if (now >= payoutPeriodStart + 10 days) {
            owner.transfer(this.balance);
        }
    }

    function changeOwner(address newOwner)
        onlyBy(owner)
    {
        owner = newOwner;
    }
    //---------------------------------------------------------

    //==================== ENTRANT INTERACTIONS ====================
    /// Entrants can use this function to submit a quiz entry
    function enterQuiz(string entryAnswers, uint gas) payable
        onlyState(QuizState.inProgress)
        returns(string)
    {
        // check if entry fee is sufficient
        require(msg.value >= _entryFee);

        uint oraclizeCostEstimate = oraclize_getPrice("URL");

        if (oraclizeCostEstimate > msg.value) {
            LogNewOraclizeQueryError("Oraclize query was NOT sent, please send more ETH to cover for the query fee");
            revert();
        }
        else {
            // subract infrastructure and admin commission
            uint factor = (msg.value - oraclizeCostEstimate) * _adminPercentage;
            uint entrantFunding = (msg.value - oraclizeCostEstimate) - (factor / 100);

            // constrct new entry
            Entry memory newEntry;
            newEntry.entrantAddress = msg.sender;
            newEntry.entryFunds = entrantFunding;
            newEntry.answersString = entryAnswers;
            newEntry.oriclizeCost = oraclizeCostEstimate;

            string memory paramsPartA = ' {"answers":"';
            string memory paramsPartC = '"}';
            string memory params = strConcat(paramsPartA, entryAnswers, paramsPartC);

            // fire oracle query
            bytes32 queryId = oraclize_query("URL", _answerOutcomeUrl, params, gas);

            // add query id to sender mapping
            _oracleAnswersMapping[queryId] = msg.sender;

            // add new entry to entries mapping
            entries[msg.sender] = newEntry;

            // add entrant funding to reward pool
            rewardPool += entrantFunding;

            totalEntries ++;

            LogNewEntry(_quizId, msg.sender, rewardPool, totalEntries, getNumCorrectEntries());

            return params;
        }
    }

    /// Entrants can use this function to check if they have unclaimed winnings
    function getEntryOutcome() constant
        returns(uint)
    {
        if(winners[msg.sender] > 0) {
            return winners[msg.sender];
        }
        return 0;
    }

    /// Entrants can use this function to claim their winnings 
    function claimWinnings()
        onlyState(QuizState.payout)
        returns(uint)
    {
        if(winners[msg.sender] > 0) {
            uint winAmount = winners[msg.sender];

            require(this.balance >= winAmount);
            
            // prevent replay
            winners[msg.sender] = 0;

            // entrant is winner and has unclaimed winnings, transact their split
            msg.sender.transfer(winAmount);

            return winAmount;
        }

        return 0;
    }

    function refundEntry()
        onlyState(QuizState.refund)
        returns(uint)
    {
        if(entries[msg.sender].entryFunds > 0) {
            var refundAmount = entries[msg.sender].entryFunds;

            require(this.balance >= refundAmount);

            // prevent replay
            entries[msg.sender].entryFunds = 0;

            // entry exists, and has not been refunded
            msg.sender.transfer(refundAmount);
        }

        return 0;
    }
    //---------------------------------------------------------

    //==================== ORACLE ====================
    function __callback(bytes32 qId, string result) {
        if (msg.sender != oraclize_cbAddress()) throw;

        if(_oracleAnswersMapping[qId] != 0) {
            // retrieve the entrant's address from query ID mapping
            address entrantAddress = _oracleAnswersMapping[qId];

            if(parseInt(result) == 1) {
                // answer was correct
                correctEntriesArray.push(entries[entrantAddress]);
            }
        }
        else {
            throw;
        }
    }
    //--------------------------------------------------------------
}

/*
TODOS:
- function for retrieving an entry
- double-check function and variable scoping one last time

FUTURE FEATURES:
- retrieval of winners with entry amounts
- set quiz start/end date & ignore submissions prior or after
- ability to set questions / answers
- use block hashes to pick random winners (in development)
- make quiz reusable
    - ability to set admin comission percentage
    - ability to set decrypt hash
*/
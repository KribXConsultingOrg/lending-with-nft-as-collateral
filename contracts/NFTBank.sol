pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";




contract NFTBank is Ownable {

    uint public loanId;
    uint public applicationId;
    uint public millisecondsInMonth = 2629800000;
    uint bankFee;
    uint bankCommission;

    

    struct loan{

        uint _loanId;
        address _nftAddress;
        uint _tokenId;
        address _lender;
        address _lendee;
        uint interestRate;
        uint _tenure;
        uint _loanAmount;
        uint _withdrawLimit;
        uint _endTime;
        uint _emi;
        bool _closed;
        

    }

    struct loanPayment{
        uint _loanId;
        uint _paidBack;
        bool _default;
    }

    struct loanApplication{
        
        uint _applicationId;
        address _nftAddress;
        uint _tokenId;
        address _lendee;
        uint _interestRate;
        uint _tenure;
        uint _loanAmount;
        bool _approved;
        

    }

    mapping(uint=>loan) public allLoans;
    mapping(address => uint[]) public lendeeLoans;
    mapping(address => uint[]) public lenderLoans;

    mapping(uint=>loanPayment) public loanPayments;

    mapping(uint=>loanApplication) public allApplications;
    mapping(address=>loanApplication[]) public loanApplications;


    function applyForLoan(address _nftAddress, uint _nftId, uint _interestRate, uint _tenure, uint _amount) public {

        require(IERC721(_nftAddress).ownerOf(_nftId)==msg.sender, "Wallet does not own this NFT");
        

        applicationId+=1;
        loanApplications[msg.sender].push(loanApplication(applicationId, _nftAddress, _nftId, msg.sender, _interestRate, _tenure, _amount, false));
        allApplications[applicationId] = loanApplication(applicationId, _nftAddress, _nftId, msg.sender, _interestRate, _tenure, _amount, false);



    }

    struct offer{
        
        uint _applicationId;
        address _lender;
        uint _interestRate;
        bool _cancelOffer;
        bool _accepted;
        bool _refund;

    }

    mapping(uint =>offer[]) public offers;
    mapping(uint=>uint) public interestOffered;
    mapping(uint=>address) public offerCreators;
    mapping(uint=>offer) public totalOffers;

    uint offerId;

    function createOffer(uint _applicationId, uint _interestRate) public payable {

        require(applicationId>=_applicationId,"This application does not exist");
        require(allApplications[_applicationId]._approved==false, "Loan application already approved");
        require(msg.value>=allApplications[_applicationId]._loanAmount);

        offerId+=1;        

        offers[_applicationId].push(offer(_applicationId,msg.sender, _interestRate, false,false, false));
        interestOffered[offerId]= _interestRate;
        offerCreators[offerId]=msg.sender;
        totalOffers[offerId]= offer(_applicationId,msg.sender, _interestRate, false,false, false);
        
    }

    function cancelOffer(uint _offerId) public{

        require(totalOffers[_offerId]._lender==msg.sender);
        require(totalOffers[_offerId]._refund==false);
        require(totalOffers[_offerId]._accepted==false);

        address payable receiver = payable(totalOffers[_offerId]._lender);
        

        if(receiver.send(allApplications[totalOffers[_offerId]._applicationId]._loanAmount)){
            totalOffers[_offerId]._refund=true;

        }

    }

    function acceptOffer(uint _offerId) public {

        uint _applicationId = totalOffers[_offerId]._applicationId;

        require(allApplications[_applicationId]._lendee==msg.sender,"This wallet did not create this application");
        require(totalOffers[_offerId]._cancelOffer==false);
        

        allApplications[_applicationId]._interestRate = interestOffered[_offerId];

        if(processLoanApplication(_applicationId, interestOffered[_offerId],offerCreators[offerId],msg.sender,
         allApplications[_applicationId]._loanAmount)){

            totalOffers[_offerId]._accepted=true;
         }



    }

    function lend(uint _applicationId) public payable{

        require(msg.value>=allApplications[_applicationId]._loanAmount);
        processLoanApplication(_applicationId, allApplications[_applicationId]._interestRate, msg.sender,allApplications[_applicationId]._lendee, msg.value );

    }

    

    function processLoanApplication(uint _applicationId, uint _interestRate, address _lender, address _lendee, uint _loanAmount) private returns(bool) {

        require(allApplications[_applicationId]._approved==false, "Loan application already approved");

        require(IERC721(allApplications[_applicationId]._nftAddress).ownerOf(allApplications[_applicationId]._tokenId)==allApplications[_applicationId]._lendee, "Wallet does not own this NFT");
        

        
        //Seize the colletral
        IERC721(allApplications[_applicationId]._nftAddress).transferFrom(_lendee, address(this), 
        allApplications[_applicationId]._tokenId);

        //Create Loan
        loanId+=1;
        uint _endTime = block.timestamp + (allApplications[_applicationId]._tenure)*millisecondsInMonth;

        uint _emi=calculateEMI( _interestRate, _loanAmount, allApplications[_applicationId]._tenure);

        allLoans[loanId]=loan(loanId,allApplications[_applicationId]._nftAddress, 
        allApplications[_applicationId]._tokenId,_lender,
        _lendee, _interestRate,allApplications[_applicationId]._tenure, _loanAmount, _loanAmount, 
        _endTime,_emi, false);

        loanPayments[loanId]=loanPayment(loanId,0,false);

        allApplications[_applicationId]._approved=true; 



        lendeeLoans[_lendee].push(loanId);

        lenderLoans[_lender].push(loanId);

        return(true);

        

    }
    function calculateEMI(uint _interestRate, uint _loanAmount, uint _tenure) private returns(uint){

        
        uint a = SafeMath.mul(_interestRate, _loanAmount);
        uint _totalinterest = SafeMath.div(a,1000);
        uint _emi = SafeMath.div(_totalinterest,_tenure);
        
        return(_emi);



    }

    function withdrawLoanAmount(uint _loanId, uint _amount) public {

        require(allLoans[_loanId]._lendee==msg.sender);
        require(allLoans[_loanId]._withdrawLimit>=_amount);
        require(_amount>0);

        address payable receiver = payable(msg.sender);        

        if(receiver.send(_amount)){
            allLoans[loanId]._withdrawLimit = allLoans[loanId]._withdrawLimit - _amount;

        }


    }

    function payEMI(uint _loanId) public payable {

        require(allLoans[_loanId]._closed==false);
        require(loanPayments[_loanId]._paidBack<=allLoans[_loanId]._loanAmount);

        loanPayments[_loanId]._paidBack += msg.value;

        uint commission = msg.value*bankFee/1000;

        bankCommission+=commission;


    }

    function closePaidUpLoan(uint _loanId) public {

        uint _payableAmount = allLoans[_loanId]._loanAmount +(allLoans[_loanId]._emi*allLoans[_loanId]._tenure);

        require(_payableAmount<=loanPayments[_loanId]._paidBack);

        IERC721(allLoans[_loanId]._nftAddress).transferFrom(address(this),allLoans[_loanId]._lendee, 
        allLoans[_loanId]._tokenId);

        allLoans[_loanId]._closed = true;
        


        

    }

    function closeDefaultedLoan(uint _loanId) public{
        require(block.timestamp>=allLoans[_loanId]._endTime);
        uint _payableAmount = allLoans[_loanId]._loanAmount +(allLoans[_loanId]._emi*allLoans[_loanId]._tenure);
        require(_payableAmount>=loanPayments[_loanId]._paidBack);
        IERC721(allLoans[_loanId]._nftAddress).transferFrom(address(this),allLoans[_loanId]._lender , 
        allLoans[_loanId]._tokenId);
        allLoans[_loanId]._closed = true;
        loanPayments[_loanId]._default = true;


    }

    function setFee(uint _bankFee) public onlyOwner{
        bankFee =_bankFee;
    }

    //Contract Owner can withdraw his commission from transactions
    function withdrawDevCommission() public onlyOwner{
        address payable receiver = payable(owner());
        require(bankCommission>0);

        if(receiver.send(bankCommission)){
            bankCommission =0;

        }
    }



    
    
}
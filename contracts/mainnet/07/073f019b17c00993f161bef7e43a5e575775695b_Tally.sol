pragma solidity ^0.4.24;


contract Tally {

    struct Verifier {
        address voterAdress;
        string  county;
        string constituency;
        string  ward;
        string pollingId;
        string pollingName;
        uint cand1;
        uint cand2;
        uint cand3;
        uint cand4;}

    Verifier[] public verifiersList;
    mapping (address => bool) public admins;
    mapping (address => bool) public owners;
    mapping (address => bool) public verifiers;
    mapping (address => bool) public superOwner;
    uint public cand1Count;
    uint public cand2Count;
    uint public cand3Count;
    uint public cand4Count;
    uint public sum;

    modifier restricted(){
      bool isAdmin = admins[msg.sender];
      require(isAdmin);
      _;}
      modifier owner(){
      bool isOwner = owners[msg.sender];
      require(isOwner);
      _;}

    modifier voterOnly (){
    bool isVoter = verifiers[msg.sender];
    require(isVoter);
    _;}
    modifier superOnly (){
    bool isSuperOwner = superOwner[msg.sender];
    require(isSuperOwner);
    _;}
     //constructor argument 
    constructor() public{
    superOwner[msg.sender] = true;
    admins[msg.sender] = true;
    owners[msg.sender] = true;
    verifiers[msg.sender] = true;}
    
    function addAdmin(address admin) public owner superOnly {
      admins[admin] = true;
      verifiers[admin] = true;}

    function removeAdmin(address admin) public owner superOnly  {
     admins[admin] = false;}

    function addOwners(address ownerz) public superOnly {
      owners[ownerz] = true;
      admins[ownerz] = true;
      verifiers[ownerz] = true;}

    function removeOwner(address ownerz) public superOnly  {
     owners[ownerz] = false;}

    function addVerifier(address verify) public restricted owner superOnly {
     verifiers[verify] = true;}

    function removeVerifier(address verify) public restricted owner superOnly {
     verifiers[verify] = false;}

    function createRequest(string county , string constituency,string ward,
    string pollingId,string pollingName,
    uint cand1, uint cand2,
    uint cand3 , uint cand4 )
    public  voterOnly {
      Verifier memory newRequest= Verifier({
        county : county, 
        constituency: constituency, 
        ward : ward,
        pollingId : pollingId ,
        pollingName:  pollingName,
        cand1 : cand1,
        cand2 : cand2,
        cand3 : cand3,
        cand4 : cand4,
        voterAdress : msg.sender
      });
      verifiersList.push(newRequest);
      cand1Count = cand1 + cand1Count;
      cand2Count = cand2 + cand2Count;
      cand3Count = cand3 + cand3Count;
      cand4Count = cand4 + cand4Count;
      sum = cand1Count + cand2Count + cand3Count + cand4Count;
      
      }

      function getRequestCount() public view returns(uint){
        return verifiersList.length;}

      function getFinalResults() public view returns (uint, uint ,uint, uint, uint){
        return (
          cand1Count,
          cand2Count,
          cand3Count,
          cand4Count,
          sum 
        );
      }

}
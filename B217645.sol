// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // protects against reentrancy attacks


/// @title VickreyAuction
/// @author B217645
/// @notice This contract conducts a sealed bid Vickrey Auction
contract VickreyAuction is ReentrancyGuard {

    /// STRUCTS

    // represents a single auction with all relevant parameters
    struct Auction {
        address seller;  // address of the seller
        IERC721 nft; // address of the NFT collection
        uint256 tokenId; // unique ID for specific nft 
        uint256 reservePrice; // minimum auction price
        uint256 endOfBidding; // length of bidding process
        uint256 endOfRevealing; // length of revealing process
        uint256 forfeitClaimDeadline; // time limit in which seller has to claim forfeited funds
        uint256 initialDeposit; // necessary deposit to place a bid

        uint256 highestBid; // value of current highest bid 
        uint256 secondHighestBid; // value of current second highest bid
        address highestBidder; // address of current highest bidder

        bool auctionEnded; // whether auction has been finalized
        bool nftClaimed; // whether nft has already been claimed
        bool sellerWithdrawn; // whether seller has withdrawn their payment from auction

        mapping(address => bool) revealed; // whether a bidder has revealed their bid
        mapping(address => uint256) deposit; // amount deposited by bidder (including top-ups)
        mapping(address => bytes32) hashedBid; // hashedbid made by bidder
        mapping(address => bool) forfeited; // whether bidder's deposit has been forfeited
        address[] bidders; // list of addresses who placed a sealed bid
    }

    // struct for users to get auction info whilst it is still ongoing
     struct AuctionInfo {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 initialDeposit;
        uint256 endOfBidding;
        uint256 endOfRevealing;
        bool auctionEnded;
    }

    // struct for users to get results of auction upon completion
    struct AuctionResults {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 reservePrice;
        uint256 initialDeposit;
        uint256 endOfBidding;
        uint256 endOfRevealing;
        uint256 highestBid;
        address highestBidder;
        uint256 secondHighestBid;
        bool nftClaimed;
    }


    // assign each auction a unique auction ID
    uint256 public auctionCount = 0;
    mapping(uint256 => Auction) private auctions;  // private because solidity cannot return mappings inside "Auction" struct



    /// EVENTS

    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address nftContract, uint256 tokenId, uint256 reservePrice, uint256 initialDeposit, uint256 endOfBidding, uint256 endOfRevealing); // a new auction has been created
    event BidPlaced(uint256 indexed auctionId, address indexed bidder); // a bid has been placed
    event BidRevealed(uint256 indexed auctionId, address indexed bidder, uint256 amount); // a bid has been revealed
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 highestBid, uint256 secondHighestBid); // an auction has ended
    event Withdrawn(uint256 indexed auctionId, address indexed user, uint256 amount); // funds have been withdrawn
    event NFTClaimed(uint256 indexed auctionId, address indexed winner, uint256 tokenId); // NFT has been claimed by winner
    event NFTReclaimed(uint256 indexed auctionId, address indexed seller, uint256 tokenId); // NFT has been reclaimed by seller
    event DepositForfeited(uint256 indexed auctionId, address indexed bidder, uint256 amount); // a deposit has been forfeited
    event ForfeitedClaimed(uint256 indexed auctionId, address indexed seller, uint256 totalAmount); // a forfeited deposit has been claimed by seller
    event UnclaimedDepositRecovered(uint256 indexed auctionId, address indexed bidder, uint256 amount); // a forfeited deposit has been reclaimed by the bidder



    /// MODIFIERS
    
    // only seller can call this function
    modifier onlySeller(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].seller, "Only seller can call function");
        _;
    }

    // only callable during the bidding period
    modifier onlyDuringBidding(uint256 auctionId) {
        require(block.timestamp <= auctions[auctionId].endOfBidding, "Bidding period ended");
        _;
    }

    // only callable during the reveal period
    modifier onlyDuringReveal(uint256 auctionId) {
        require(block.timestamp > auctions[auctionId].endOfBidding, "Bidding period not ended");
        require(block.timestamp <= auctions[auctionId].endOfRevealing, "Reveal period ended");
        _;
    }

    // only callable after the reveal period
    modifier onlyAfterReveal(uint256 auctionId) {
        require(block.timestamp > auctions[auctionId].endOfRevealing, "Reveal period not ended");
        _;
    }

    // only allow function if NFT has not been claimed yet
    modifier onlyIfNFTNotClaimed(uint256 auctionId) {
        require(!auctions[auctionId].nftClaimed, "NFT already claimed");
        _;
    }

    // only callable after auction has officially been ended/finalised
    modifier onlyAfterAuctionEnded(uint256 auctionId) {
    require(auctions[auctionId].auctionEnded, "Auction not ended yet");
    _;
    }

    // checks auction you are calling function for exists
    modifier auctionExists(uint256 auctionId) {
    require(auctions[auctionId].seller != address(0), "Auction does not exist");
    _;
    }


    // Only callable while the seller is allowed to claim forfeited deposits
    modifier onlyDuringClaim(uint256 auctionId) {
        require(block.timestamp <= auctions[auctionId].forfeitClaimDeadline, "Claim period ended");
        require(block.timestamp > auctions[auctionId].endOfRevealing, "Claim period not started");
        _;
    }

    // Only callable after the seller’s claim window has closed
    modifier onlyAfterClaim(uint256 auctionId) {
        require(block.timestamp > auctions[auctionId].forfeitClaimDeadline, "Claim period not ended");
        _;
    }



    /// FUNCTIONS


    /// @notice Creates a new auction
    /// @param _nft address of the NFT collection 
    /// @param _tokenId unique ID for specific nft 
    /// @param _reservePrice minimum auction price 
    /// @param _biddingPeriod length of bidding period 
    /// @param _revealingPeriod length of revealing period 
    /// @param _initialDeposit deposit to bid in auction 
    function createAuction(IERC721 _nft, uint256 _tokenId, uint256 _reservePrice, uint32 _biddingPeriod, uint32 _revealingPeriod, uint256 _initialDeposit) 
        external {

        require(address(_nft) != address(0), "NFT contract requires address");
        require(_biddingPeriod >= 180 && _revealingPeriod >= 180, "Bid & reveal periods too short"); // set as low values for testing purposes
        require(_biddingPeriod <= 4 * _revealingPeriod, "Needs bid period <= 4 * reveal period");
        require(_reservePrice > 0, "Reserve price must be > 0");
        require(_nft.ownerOf(_tokenId) == msg.sender, "You do not own this NFT");
        require(_initialDeposit > 0, "Initial deposit must be > 0");
        require(_reservePrice >= _initialDeposit, "Reserve must be >= deposit");

        uint256 auctionId = auctionCount++; // gives auction an ID value

        // initialise parameters for specific auction
        Auction storage a = auctions[auctionId]; // shortened auction identifier
        a.seller = msg.sender;
        a.nft = _nft;
        a.tokenId = _tokenId;
        a.reservePrice = _reservePrice;
        a.initialDeposit = _initialDeposit;
        a.endOfBidding = block.timestamp + _biddingPeriod;
        a.endOfRevealing = a.endOfBidding + _revealingPeriod;
        a.forfeitClaimDeadline = a.endOfRevealing + _revealingPeriod; // same amount of time as reveal period

        // transfer NFT to contract
        _nft.transferFrom(msg.sender, address(this), _tokenId);

        emit AuctionCreated(auctionId, msg.sender, address(_nft), _tokenId, _reservePrice, _initialDeposit, a.endOfBidding, a.endOfRevealing);
    }

    
    /// @notice Bidders place sealed bid accompanied by deposit
    /// @param auctionId auction bidder wants to participate in 
    /// @param hash encrypted bid (computed off-chain) 
    function placeSealedBid(uint256 auctionId, bytes32 hash) 
        external payable auctionExists(auctionId) onlyDuringBidding(auctionId) {

        Auction storage a = auctions[auctionId];
        require(msg.sender != a.seller, "Seller cannot bid");
        require(msg.value == a.initialDeposit, "Must send initial deposit");
        require(a.hashedBid[msg.sender] == bytes32(0), "Bid already placed");

        a.hashedBid[msg.sender] = hash; // maps hashed bid to bidder
        a.deposit[msg.sender] = msg.value; // maps deposit value to bidder
        a.bidders.push(msg.sender); // adds bidder to list of all bidders

        emit BidPlaced(auctionId, msg.sender); // deposit value is same for everyone so is not emitted
    }


    /// @notice Bidders reveal their bid after bidding period ends
    /// @param auctionId auction bidder participated in 
    /// @param amount value bid by bidder 
    /// @param nonce secret number chosen by bidder to compute hash
    function reveal(uint256 auctionId, uint256 amount, uint256 nonce) 
        external payable onlyDuringReveal(auctionId) auctionExists(auctionId) {

        Auction storage a = auctions[auctionId];
        require(!a.revealed[msg.sender], "Already revealed");
        require(a.hashedBid[msg.sender] != bytes32(0), "No bid placed");
        require(keccak256(abi.encode(msg.sender, amount, nonce)) == a.hashedBid[msg.sender], "Invalid reveal"); // commitment unique per bidder, no encoding ambiguity, negligible gas overhead

        if (amount > a.deposit[msg.sender]) {
            uint256 remaining = amount - a.deposit[msg.sender]; // Calculate the remaining amount to be sent
            require(msg.value == remaining, "Send remaining bid amount");
            a.deposit[msg.sender] += msg.value; // update deposit amount
        } else {
            require(msg.value == 0, "No extra ETH needed");
        }

        // mark sender as having revealed
        a.revealed[msg.sender] = true;

        // updates highest and second highest bids with priority for first to reveal in the case of ties
        if (amount > a.highestBid && amount >= a.reservePrice) {
            a.secondHighestBid = a.highestBid;
            a.highestBid = amount;
            a.highestBidder = msg.sender;
        } else if (amount > a.secondHighestBid && amount >= a.reservePrice) {
            a.secondHighestBid = amount;
        }
        
        emit BidRevealed(auctionId, msg.sender, amount);
    }


    /// @notice Seller or bidder marks auction as ended after reveal period finishes
    /// @param auctionId auction seller or bidder participated in     
    function endAuction(uint256 auctionId) 
        external auctionExists(auctionId) onlyAfterReveal(auctionId) {

        Auction storage a = auctions[auctionId];
        require(!a.auctionEnded, "Auction already ended");
        a.auctionEnded = true; // mark auction as finalized
        
        if (a.secondHighestBid >= a.reservePrice) {
            emit AuctionEnded(auctionId, a.highestBidder, a.highestBid, a.secondHighestBid);
        } else {
            emit AuctionEnded(auctionId, a.highestBidder, a.highestBid, a.reservePrice);
        }       
    }


    /// @notice Seller and bidder withdraws funds after auction has ended
    /// @param auctionId auction seller or bidder participated in
    function withdraw(uint256 auctionId) 
        external nonReentrant auctionExists(auctionId) onlyAfterAuctionEnded(auctionId) {

        Auction storage a = auctions[auctionId];
        uint256 value; // amount seller or bidder must receive

        // case 1: Seller
        if (msg.sender == a.seller) {
            require(!a.sellerWithdrawn, "Already withdrawn"); 
            a.sellerWithdrawn = true; // prevents seller attempting multiple withdrawels
            require(a.highestBid >= a.reservePrice, "No valid bids");
            if (a.secondHighestBid >= a.reservePrice) {
                value = a.secondHighestBid;
            } // case where two valid bids are made above the reserve price
            else {
                value = a.reservePrice;
            } // case where zero or one valid bid is made above reserve price
        }
        
        // Case 2: Winner
        else if (msg.sender == a.highestBidder) {
            if (a.secondHighestBid >= a.reservePrice) {
                value = a.deposit[msg.sender] - a.secondHighestBid;
            } // case where two valid bids are made above the reserve price
            else {
                value = a.deposit[msg.sender] - a.reservePrice;
            } // case where one valid bid is made above reserve price
        } 
        
        // Case 3: Losing Bidders
        else {
            require(a.revealed[msg.sender], "Unrevealed bids forfeited"); // those who didn't reveal bids lose their deposit
            value = a.deposit[msg.sender];
        }

        require(value > 0, "No funds to withdraw"); //  stops wasting gas on a zero withdrawel
        a.deposit[msg.sender] = 0; // reset deposit to prevent bidders attempting multiple withdrawals 

        (bool ok, ) = msg.sender.call{value: value}(""); 
        require(ok, "Transfer failed");

        emit Withdrawn(auctionId, msg.sender, value);
    }


    /// @notice Winner can claim NFT after auction ends
    /// @param auctionId auction bidder participated in
    function claimNFT(uint256 auctionId) 
        external nonReentrant auctionExists(auctionId) onlyAfterAuctionEnded(auctionId) onlyIfNFTNotClaimed(auctionId) {

        Auction storage a = auctions[auctionId];
        require(msg.sender == a.highestBidder, "you are not highest bidder"); // Only the highest bidder can claim the NFT

        a.nftClaimed = true;
        a.nft.safeTransferFrom(address(this), a.highestBidder, a.tokenId);

        emit NFTClaimed(auctionId, a.highestBidder, a.tokenId);
    }
 

    /// @notice Seller can reclaim NFT after auction ends if there were no valid bids
    /// @param auctionId auction seller participated in
    function reclaimNFT(uint256 auctionId) 
        external nonReentrant auctionExists(auctionId) onlySeller(auctionId) onlyAfterAuctionEnded(auctionId) onlyIfNFTNotClaimed(auctionId) {

        Auction storage a = auctions[auctionId];
        require(a.highestBid < a.reservePrice, "There was a valid bid");

        a.nftClaimed = true;
        a.nft.safeTransferFrom(address(this), a.seller, a.tokenId);

        emit NFTReclaimed(auctionId, a.seller, a.tokenId);
    }


    /// @notice Seller can Claim forfeited deposits in batches
    /// @param auctionId auction seller participated in
    /// @param biddersToClaim list of bidders to claim from
    /// @param maxBatch maximum number of bidders to claim from in one instance for gas limit reasons
    function claimForfeitedBatch(uint256 auctionId, address[] calldata biddersToClaim, uint16 maxBatch) 
        external auctionExists(auctionId) onlySeller(auctionId) nonReentrant onlyAfterAuctionEnded(auctionId) onlyDuringClaim(auctionId) {

        Auction storage a = auctions[auctionId]; 
        uint256 total; // amount to transfer to seller
        uint16 count; // to ensure batch size limit is not violated

        for (uint256 i = 0; i < biddersToClaim.length && count < maxBatch; ++i) {
            address b = biddersToClaim[i];
            // if bidder failed to reveal and hasn't already forfeited deposit
            if (!a.revealed[b] && !a.forfeited[b] && a.deposit[b] > 0) { 
                uint256 amt = a.deposit[b]; 
                a.deposit[b] = 0;
                a.forfeited[b] = true; // zeros deposit and marks deposit as forfeited before adding to the total
                total += amt;
                count++;
                emit DepositForfeited(auctionId, b, amt); // records which bidder has forfeited their deposit
            }
        }

        require(total > 0, "No deposits to claim"); // prevents wasting gas on a zero value claim
        (bool ok, ) = a.seller.call{value: total}("");
        require(ok, "Transfer failed");

        emit ForfeitedClaimed(auctionId, a.seller, total); 
    }


    /// @notice Bidders who failed to reveal can claim their deposit back after seller's claim period ends
    /// @param auctionId auction bidder participated in
    function recoverUnclaimedDeposit(uint256 auctionId)
        external auctionExists(auctionId) nonReentrant onlyAfterAuctionEnded(auctionId) onlyAfterClaim(auctionId) {
            
        Auction storage a = auctions[auctionId];
        require(!a.revealed[msg.sender], "Bid was revealed");
        require(!a.forfeited[msg.sender], "Deposit already forfeited");
        uint256 amount = a.deposit[msg.sender];
        require(amount > 0, "Nothing to recover");

        a.deposit[msg.sender] = 0;
        a.forfeited[msg.sender] = true;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit UnclaimedDepositRecovered(auctionId, msg.sender, amount);
    }


    /// @notice Computes the hash of a bid for use in a Vickrey auction commitment
    /// @param bidder the address of the bidder using function
    /// @param amount the bid made by the bidder
    /// @param nonce secret number chosen by bidder
    /// @dev This function is pure and can be called off-chain to generate the hashed bid. 
    ///      The hash is computed using `abi.encode(bidder, amount, nonce)`.
    ///      It does not interact with contract storage or state.
    function computeHash(address bidder, uint256 amount, uint256 nonce) external pure returns (bytes32) {
        return keccak256(abi.encode(bidder, amount, nonce));
    }



    /// GETTER FUNCTIONS

    /// @notice Returns key information about a specific auction
    /// @param auctionId the specific auction that info is required for
    /// @dev can be called off chain for no gas cost
    function getAuctionInfo(uint256 auctionId)
        external view auctionExists(auctionId) returns (AuctionInfo memory info) {

        Auction storage a = auctions[auctionId];
        info = AuctionInfo({
            seller: a.seller,
            nftContract: address(a.nft),
            tokenId: a.tokenId,
            initialDeposit: a.initialDeposit,
            endOfBidding: a.endOfBidding,
            endOfRevealing: a.endOfRevealing,
            auctionEnded: a.auctionEnded
        });
    }


    /// @notice Returns key information and results about a specific auction after it has ended
    /// @param auctionId the specific auction that info is required for
    /// @dev can be called off chain for no gas cost
    function getAuctionResults(uint256 auctionId) 
        external view auctionExists(auctionId) onlyAfterAuctionEnded(auctionId) returns (AuctionResults memory results) {

        Auction storage a = auctions[auctionId];
        results = AuctionResults({
            seller: a.seller,
            nftContract: address(a.nft),
            tokenId: a.tokenId,
            reservePrice: a.reservePrice,
            initialDeposit: a.initialDeposit,
            endOfBidding: a.endOfBidding,
            endOfRevealing: a.endOfRevealing,
            highestBid: a.highestBid,
            highestBidder: a.highestBidder,
            secondHighestBid: a.secondHighestBid,
            nftClaimed: a.nftClaimed
        });
    }


    /// @notice Returns the hashed bid submitted by a specific bidder
    /// @param auctionId auction bidder participated in
    /// @param bidder address of the specific bidder
    /// @dev can be called off chain for no gas cost
    function getBidHash(uint256 auctionId, address bidder) external view returns (bytes32) {
        return auctions[auctionId].hashedBid[bidder];
    }

    /// @notice Returns the total deposit currently held for a bidder
    /// @param auctionId auction bidder participated in
    /// @param bidder address of the specific bidder
    /// @dev can be called off chain for no gas cost
    ///      deposit refers to initial deposit plus top ups
    function getDeposit(uint256 auctionId, address bidder) external view returns (uint256) {
        return auctions[auctionId].deposit[bidder];
    }

    /// @notice Returns whether a bidder has revealed their bid
    /// @param auctionId auction bidder participated in
    /// @param bidder address of the specific bidder
    /// @dev can be called off chain for no gas cost
    function hasRevealed(uint256 auctionId, address bidder) external view returns (bool) {
        return auctions[auctionId].revealed[bidder];
    }

    /// @notice Returns whether a bidder’s deposit has been forfeited
    /// @param auctionId auction bidder participated in
    /// @param bidder address of the specific bidder
    /// @dev can be called off chain for no gas cost
    function hasForfeited(uint256 auctionId, address bidder) external view returns (bool) {
        return auctions[auctionId].forfeited[bidder];
    }

    /// @notice Returns the list of all bidder addresses for a given auction
    /// @param auctionId the specific auction that info is required for
    /// @dev can be called off chain for no gas cost
    function getBidders(uint256 auctionId) external view returns (address[] memory) {
        return auctions[auctionId].bidders;
    }
}
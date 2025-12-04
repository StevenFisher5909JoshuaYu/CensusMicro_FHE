// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract HistoricalCensusAnalysisFHE is SepoliaConfig {
    struct EncryptedRecord {
        uint256 id;
        address researcher;
        euint32 encryptedAge;          // Encrypted age
        euint32 encryptedBirthYear;    // Encrypted birth year
        euint32 encryptedOccupation;   // Encrypted occupation code
        euint32 encryptedLocation;     // Encrypted location code
        euint32 encryptedFamilySize;   // Encrypted family size
        uint256 timestamp;
    }
    
    struct AnalysisResult {
        euint32 averageAge;            // Encrypted average age
        euint32 occupationDistribution; // Encrypted occupation distribution
        euint32 mobilityIndex;         // Encrypted mobility index
        bool isCompleted;
    }
    
    struct DecryptedResult {
        uint32 averageAge;
        uint32 occupationDistribution;
        uint32 mobilityIndex;
        bool isRevealed;
    }

    uint256 public recordCount;
    mapping(uint256 => EncryptedRecord) public encryptedRecords;
    mapping(uint256 => AnalysisResult) public analysisResults;
    mapping(uint256 => DecryptedResult) public decryptedResults;
    
    mapping(address => uint256[]) private researcherRecords;
    mapping(address => bool) private authorizedResearchers;
    
    mapping(uint256 => uint256) private requestToAnalysisId;
    
    event RecordSubmitted(uint256 indexed id, address indexed researcher);
    event AnalysisRequested(uint256 indexed id);
    event AnalysisCompleted(uint256 indexed id);
    event ResultDecrypted(uint256 indexed id);
    
    address public archiveAdmin;
    
    modifier onlyAdmin() {
        require(msg.sender == archiveAdmin, "Not admin");
        _;
    }
    
    modifier onlyAuthorized() {
        require(authorizedResearchers[msg.sender], "Not authorized");
        _;
    }
    
    constructor() {
        archiveAdmin = msg.sender;
    }
    
    /// @notice Authorize a researcher
    function authorizeResearcher(address researcher) public onlyAdmin {
        authorizedResearchers[researcher] = true;
    }
    
    /// @notice Submit encrypted census record
    function submitEncryptedRecord(
        euint32 encryptedAge,
        euint32 encryptedBirthYear,
        euint32 encryptedOccupation,
        euint32 encryptedLocation,
        euint32 encryptedFamilySize
    ) public onlyAuthorized {
        recordCount += 1;
        uint256 newId = recordCount;
        
        encryptedRecords[newId] = EncryptedRecord({
            id: newId,
            researcher: msg.sender,
            encryptedAge: encryptedAge,
            encryptedBirthYear: encryptedBirthYear,
            encryptedOccupation: encryptedOccupation,
            encryptedLocation: encryptedLocation,
            encryptedFamilySize: encryptedFamilySize,
            timestamp: block.timestamp
        });
        
        analysisResults[newId] = AnalysisResult({
            averageAge: FHE.asEuint32(0),
            occupationDistribution: FHE.asEuint32(0),
            mobilityIndex: FHE.asEuint32(0),
            isCompleted: false
        });
        
        decryptedResults[newId] = DecryptedResult({
            averageAge: 0,
            occupationDistribution: 0,
            mobilityIndex: 0,
            isRevealed: false
        });
        
        researcherRecords[msg.sender].push(newId);
        emit RecordSubmitted(newId, msg.sender);
    }
    
    /// @notice Request social network analysis
    function requestSocialNetworkAnalysis(uint256[] memory recordIds) public onlyAuthorized {
        require(recordIds.length > 0, "No records provided");
        
        euint32 totalAge = FHE.asEuint32(0);
        euint32 occupationCounter = FHE.asEuint32(0);
        euint32 locationCounter = FHE.asEuint32(0);
        
        for (uint i = 0; i < recordIds.length; i++) {
            EncryptedRecord storage record = encryptedRecords[recordIds[i]];
            
            totalAge = FHE.add(totalAge, record.encryptedAge);
            
            // Simplified occupation distribution calculation
            occupationCounter = FHE.add(
                occupationCounter, 
                FHE.cmux(
                    FHE.eq(record.encryptedOccupation, FHE.asEuint32(1)), 
                    FHE.asEuint32(1), 
                    FHE.asEuint32(0)
                )
            );
            
            // Simplified mobility index calculation
            locationCounter = FHE.add(
                locationCounter, 
                FHE.cmux(
                    FHE.eq(record.encryptedLocation, FHE.asEuint32(2)), 
                    FHE.asEuint32(1), 
                    FHE.asEuint32(0)
                )
            );
        }
        
        // Calculate average age
        euint32 avgAge = FHE.div(totalAge, FHE.asEuint32(uint32(recordIds.length)));
        
        // Calculate mobility index (simplified)
        euint32 mobility = FHE.div(
            FHE.mul(locationCounter, FHE.asEuint32(100)), 
            FHE.asEuint32(uint32(recordIds.length))
        );
        
        // Store analysis results (using first record ID as reference)
        uint256 analysisId = recordIds[0];
        analysisResults[analysisId] = AnalysisResult({
            averageAge: avgAge,
            occupationDistribution: occupationCounter,
            mobilityIndex: mobility,
            isCompleted: true
        });
        
        emit AnalysisCompleted(analysisId);
    }
    
    /// @notice Request decryption of analysis results
    function requestResultDecryption(uint256 analysisId) public {
        AnalysisResult storage result = analysisResults[analysisId];
        require(result.isCompleted, "Analysis not completed");
        require(!decryptedResults[analysisId].isRevealed, "Results already decrypted");
        
        bytes32[] memory ciphertexts = new bytes32[](3);
        ciphertexts[0] = FHE.toBytes32(result.averageAge);
        ciphertexts[1] = FHE.toBytes32(result.occupationDistribution);
        ciphertexts[2] = FHE.toBytes32(result.mobilityIndex);
        
        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptAnalysisResult.selector);
        requestToAnalysisId[reqId] = analysisId;
        
        emit AnalysisRequested(analysisId);
    }
    
    /// @notice Process decrypted analysis results
    function decryptAnalysisResult(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 analysisId = requestToAnalysisId[requestId];
        require(analysisId != 0, "Invalid request");
        
        AnalysisResult storage aResult = analysisResults[analysisId];
        DecryptedResult storage dResult = decryptedResults[analysisId];
        require(aResult.isCompleted, "Analysis not completed");
        require(!dResult.isRevealed, "Results already decrypted");
        
        FHE.checkSignatures(requestId, cleartexts, proof);
        
        (uint32 avgAge, uint32 occDist, uint32 mobility) = 
            abi.decode(cleartexts, (uint32, uint32, uint32));
        
        dResult.averageAge = avgAge;
        dResult.occupationDistribution = occDist;
        dResult.mobilityIndex = mobility;
        dResult.isRevealed = true;
        
        emit ResultDecrypted(analysisId);
    }
    
    /// @notice Calculate family network connections
    function calculateFamilyConnections(uint256[] memory recordIds) public view returns (euint32) {
        euint32 totalConnections = FHE.asEuint32(0);
        
        for (uint i = 0; i < recordIds.length; i++) {
            EncryptedRecord storage record = encryptedRecords[recordIds[i]];
            
            // Simplified connection calculation based on family size
            totalConnections = FHE.add(
                totalConnections, 
                FHE.sub(record.encryptedFamilySize, FHE.asEuint32(1))
            );
        }
        
        return totalConnections;
    }
    
    /// @notice Retrieve researcher records
    function getResearcherRecords(address researcher) public view returns (uint256[] memory) {
        return researcherRecords[researcher];
    }
    
    /// @notice Get decrypted analysis results
    function getDecryptedResult(uint256 analysisId) public view returns (
        uint32 averageAge,
        uint32 occupationDistribution,
        uint32 mobilityIndex,
        bool isRevealed
    ) {
        DecryptedResult storage r = decryptedResults[analysisId];
        return (r.averageAge, r.occupationDistribution, r.mobilityIndex, r.isRevealed);
    }
    
    /// @notice Compute encrypted age distribution
    function computeAgeDistribution(uint256[] memory recordIds) public view returns (
        euint32 under18,
        euint32 adult,
        euint32 senior
    ) {
        for (uint i = 0; i < recordIds.length; i++) {
            EncryptedRecord storage record = encryptedRecords[recordIds[i]];
            
            under18 = FHE.add(
                under18,
                FHE.cmux(
                    FHE.lt(record.encryptedAge, FHE.asEuint32(18)),
                    FHE.asEuint32(1),
                    FHE.asEuint32(0)
                )
            );
            
            adult = FHE.add(
                adult,
                FHE.cmux(
                    FHE.and(
                        FHE.gte(record.encryptedAge, FHE.asEuint32(18)),
                        FHE.lt(record.encryptedAge, FHE.asEuint32(65))
                    ),
                    FHE.asEuint32(1),
                    FHE.asEuint32(0)
                )
            );
            
            senior = FHE.add(
                senior,
                FHE.cmux(
                    FHE.gte(record.encryptedAge, FHE.asEuint32(65)),
                    FHE.asEuint32(1),
                    FHE.asEuint32(0)
                )
            );
        }
        
        return (under18, adult, senior);
    }
}
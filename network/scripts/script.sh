#!/bin/bash

DELAY="3"
TIMEOUT="10"
VERBOSE="false"
COUNTER=1
MAX_RETRY=5

CC_SRC_PATH="irscc/"

createChannel() {
	CORE_PEER_LOCALMSPID=partya
	CORE_PEER_ADDRESS=irs-partya:7051
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/partya.example.com/users/Admin@partya.example.com/msp
	echo "===================== Creation du channel ===================== "
	peer channel create -o irs-orderer:7050 -c irs -f ./channel-artifacts/channel.tx
	echo "===================== Channel créé ===================== "
}

joinChannel () {
	for org in partya partyb 
	do
		CORE_PEER_LOCALMSPID=$org
		CORE_PEER_ADDRESS=irs-$org:7051
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/$org.example.com/users/Admin@$org.example.com/msp
		echo "===================== Org $org joignant le channel ===================== "
		peer channel join -b irs.block -o irs-orderer:7050
		echo "===================== Channel join ===================== "
	done
}
updateAnchorPeer() {
	for org in partya partyb 
	do
	echo "====================> Configuration du peer $org pour etre Anchor Peer"
		CORE_PEER_LOCALMSPID=$org
		CORE_PEER_ADDRESS=irs-$org:7051
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/$org.example.com/users/Admin@$org.example.com/msp
		peer channel update -o irs-orderer:7050 -c irs -f "./channel-artifacts/$org.tx"
    done
} 

installChaincode() {
	for org in partya partyb 
	do
		CORE_PEER_LOCALMSPID=$org
		CORE_PEER_ADDRESS=irs-$org:7051
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/$org.example.com/users/Admin@$org.example.com/msp
		echo "===================== Org $org installant la chaincode ===================== "
		peer chaincode install -n irscc -v 0 -l golang -p  ${CC_SRC_PATH}
		echo "===================== Org $org chaincode installée ===================== "
	done
}

instantiateChaincode() {
	CORE_PEER_LOCALMSPID=partya
	CORE_PEER_ADDRESS=irs-partya:7051
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/partya.example.com/users/Admin@partya.example.com/msp
	echo "===================== Instantiation de la chaincode ===================== "
	peer chaincode instantiate -o irs-orderer:7050 -C irs -n irscc -v 0 -c '{"Args":["init","Issuer","1000000","Beneficiary","50000"]}' -P "OR('partya.peer','partyb.peer')"
	echo "===================== Chaincode instantiatée ===================== "
}

## Creation du channel
sleep 1
echo "Creation channel..."
createChannel

## Joindre les peers au channel
echo "Peers joignant le channel..."
joinChannel

## MaJ anchorpeer
echo "Anchorpeer en Maj..."
updateAnchorPeer

## Installation chaincode sur les peers
echo "Installation de chaincode..."
installChaincode

# Instantiation chaincode
echo "Instantiation de chaincode..."
instantiateChaincode

echo
echo "========= Réseau IRS setup completé =========== "
echo

exit 0
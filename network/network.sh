export PATH=${PWD}/../../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}
export VERBOSE=false

# Le help
function printHelp() {
  echo "Usage: "
  echo "  start_network.sh <mode> [-t <timeout>] [-i <imagetag>] [-v]"
  echo "    <mode> - one of 'up', 'down' or 'generate'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -v - verbose mode"
  echo
  echo "Typically, one would first generate the required certificates and "
  echo "genesis block, then bring up the network."
}

# Pour faire un cleau up de l'espace docker
function clearContainers() {
  CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-.*irscc.*/) {print $1}')
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- Aucun container disponible à supprimer ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Suppression des images non désirés pour ce projet pour eviter les conflits
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev.*irscc.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "----Aucune image disponible à supprimer ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# List des versions de Fabric non désirées
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"

# Vérification des prerequis
function checkPrereqs() {
   
  LOCAL_VERSION=$(configtxgen -version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
  fi

  for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
    echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
      exit 1
    fi

    echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
      exit 1
    fi
  done
}

# Generation des certificats, du genesis block et demarrage du network.
function networkUp() {
  checkPrereqs
  # genere les artifacts s'il n'existe pas
  if [ ! -d "crypto-config" ]; then
    generateCerts
    generateChannelArtifacts
  fi
  IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE up -d orderer partya partyb cli 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Impossible de démarrer le réseau"
    exit 1
  fi
  
  docker exec cli scripts/script.sh
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Test echoué"
    exit 1
  fi
}

# Eteindre le reseau
function networkDown() {
  
  docker-compose -f $COMPOSE_FILE down --volumes --remove-orphans

  # Suppression des volumes docker
  docker run -v $PWD:/tmp/first-network --rm hyperledger/fabric-tools:$IMAGETAG rm -Rf /tmp/first-network/ledgers-backup
  # Clean up du containers de la chaincode
  clearContainers
  #Cleanup images
  removeUnwantedImages
  # suppression du orderer block et autre configuration channel et certificats
  rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
}

# Generation des certif des org utilisant cryptogen
function generateCerts() {
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen pas trouvé"
    exit 1
  fi
  echo "##### Generation des certificats utilisant cryptogen #########"

  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  cryptogen generate --config=./crypto-config.yaml
  res=$?
  if [ $res -ne 0 ]; then
    echo "Echec de generation des certificates..."
    exit 1
  fi
  echo
}

# Generate orderer genesis block and channel configuration transaction with configtxgen
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen non trouvé"
    exit 1
  fi

  echo "#########  Generation du Orderer Genesis block ##############"
  mkdir channel-artifacts
  configtxgen -profile IRSNetGenesis -outputBlock ./channel-artifacts/genesis.block -channelID system-channel
  res=$?
  if [ $res -ne 0 ]; then
    echo "Echec generation orderer genesis block..."
    exit 1
  fi
  echo
  echo "### Generation de la configuration du channel transaction 'channel.tx' ###"
  configtxgen -profile IRSChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
  res=$?
  if [ $res -ne 0 ]; then
    echo "Echec generation de la config du channel transaction..."
    exit 1
  fi
  ## Creation du anchorPeer
  echo "Creation du anchorPeer"
  createAnchorPeer
}

function createAnchorPeer() {
	#for org in partya partyb
	#do
  echo "===================== Anchorpeer partya demarre ===================== "
	configtxgen -channelID irs -profile IRSChannel -outputAnchorPeersUpdate ./channel-artifacts/partya.tx  -asOrg partya
	echo "===================== Anchorpeer partya installé ===================== "
  echo "===================== Anchorpeer partyb demarre ===================== "
  configtxgen -channelID irs -profile IRSChannel -outputAnchorPeersUpdate ./channel-artifacts/partyb.tx  -asOrg partyb
	echo "===================== Anchorpeer partyb installé ===================== "
	#done
}

CHANNEL_NAME="irs"
COMPOSE_FILE=docker-compose.yaml
COMPOSE_PROJECT_NAME=fabric-irs
#
# default image tag
IMAGETAG="latest"
# Parse commandline args
MODE=$1
shift
# Determiner si starting, stopping, generating
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting"
elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping"
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generation des certs et genesis block"
else
  printHelp
  exit 1
fi

while getopts "t:i:v" opt; do
  case "$opt" in
  t)
    CLI_TIMEOUT=$OPTARG
    ;;
  i)
    IMAGETAG=$(go env GOARCH)"-"$OPTARG
    ;;
  v)
    VERBOSE=true
    ;;
  esac
done


# Annonce de la requete
echo "${EXPMODE} pour channel '${CHANNEL_NAME}'"

#Creer le network en utilisant le docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear up du network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generation des Artifacts
  generateCerts
  generateChannelArtifacts
else
  printHelp
  exit 1
fi

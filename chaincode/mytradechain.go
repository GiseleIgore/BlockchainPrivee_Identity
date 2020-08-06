package main

import (
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)

// TradeChaincode is my Chaincode implementation
type TradeChaincode struct {
}

// Init pour initialiser le ledger
func (t *TradeChaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {
	fmt.Println("Init")
	_, args := stub.GetFunctionAndParameters()
	var Issuer, Beneficiary string            // Entities
	var Issueraccount, Beneficiaryaccount int // Asset holdings
	var err error

	if len(args) != 4 {
		return shim.Error("Nombre d'arguments incorrect. 4 au moins")
	}

	// Initialiser la chaincode
	Issuer = args[0]
	Issueraccount, err = strconv.Atoi(args[1])
	if err != nil {
		return shim.Error("valeur integer Expectée")
	}
	Beneficiary = args[2]
	Beneficiaryaccount, err = strconv.Atoi(args[3])
	if err != nil {
		return shim.Error("valeur integer Expectée")
	}
	fmt.Printf("Issueraccount = %d, Beneficiaryaccount = %d\n", Issueraccount, Beneficiaryaccount)

	// Ecriture sur le ledger
	err = stub.PutState(Issuer, []byte(strconv.Itoa(Issueraccount)))
	if err != nil {
		return shim.Error(err.Error())
	}

	err = stub.PutState(Beneficiary, []byte(strconv.Itoa(Beneficiaryaccount)))
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// Invoke Pour effectuer les transactions sur la chaine de bloc
func (t *TradeChaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	fmt.Println("Invoke")
	function, args := stub.GetFunctionAndParameters()

	if function == "invoke" {
		// Pour faire le paiement d'un compte à l'autre
		return t.invoke(stub, args)
	} else if function == "delete" {
		// pour la suppression
		return t.delete(stub, args)
	} else if function == "query" {
		// les requêtes
		return t.query(stub, args)
	}

	return shim.Error("Fonction invalide. Expecté \"invoke\" \"delete\" \"query\"")
}

// Paiment de la valeur X du compte du Issuer vers celui du Beneficiary
func (t *TradeChaincode) invoke(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	var Issuer, Beneficiary string            // Entités
	var Issueraccount, Beneficiaryaccount int // Assets
	var X int                                 // Valeur de la transaction
	var err error

	if len(args) != 3 {
		return shim.Error("Incorrect number of arguments. Expecting 3")
	}

	Issuer = args[0]
	Beneficiary = args[1]

	// Pour avoir l'etat actuel du ledger
	Issueraccountbytes, err := stub.GetState(Issuer)
	if err != nil {
		return shim.Error("Impossible d'avoir l'état du ledger")
	}
	if Issueraccountbytes == nil {
		return shim.Error("Entité non trouvée")
	}
	Issueraccount, _ = strconv.Atoi(string(Issueraccountbytes))

	Beneficiaryaccountbytes, err := stub.GetState(Beneficiary)
	if err != nil {
		return shim.Error("Impossible d'avoir l'état")
	}
	if Beneficiaryaccountbytes == nil {
		return shim.Error("Entité non trouvée")
	}
	Beneficiaryaccount, _ = strconv.Atoi(string(Beneficiaryaccountbytes))

	// Passons à l'execution
	X, err = strconv.Atoi(args[2])
	if err != nil {
		return shim.Error("Montant invalide, valeur integer expectée")
	}
	Issueraccount = Issueraccount - X
	Beneficiaryaccount = Beneficiaryaccount + X
	fmt.Printf("Issueraccount = %d, Beneficiaryaccount = %d\n", Issueraccount, Beneficiaryaccount)

	// Ecriture sur le ledger
	err = stub.PutState(Issuer, []byte(strconv.Itoa(Issueraccount)))
	if err != nil {
		return shim.Error(err.Error())
	}

	err = stub.PutState(Beneficiary, []byte(strconv.Itoa(Beneficiaryaccount)))
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// Suppression eventuelle
func (t *TradeChaincode) delete(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	if len(args) != 1 {
		return shim.Error("Nombre d'arguments incorrect. 1 au moins")
	}

	Issuer := args[0]

	// Suppression de clé
	err := stub.DelState(Issuer)
	if err != nil {
		return shim.Error("Echec")
	}

	return shim.Success(nil)
}

// Requete
func (t *TradeChaincode) query(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	var Issuer string // Entities
	var err error

	if len(args) != 1 {
		return shim.Error("Nombre d'arguments incorrect. Nom de la person requis")
	}

	Issuer = args[0]

	// Etat du ledger
	Issueraccountbytes, err := stub.GetState(Issuer)
	if err != nil {
		jsonResp := "{\"Erreur\":\"Echec pour avoir l'etat de " + Issuer + "\"}"
		return shim.Error(jsonResp)
	}

	if Issueraccountbytes == nil {
		jsonResp := "{\"Erreur\":\"Montant nul pour " + Issuer + "\"}"
		return shim.Error(jsonResp)
	}

	jsonResp := "{\"Nom\":\"" + Issuer + "\",\"Montant\":\"" + string(Issueraccountbytes) + "\"}"
	fmt.Printf("Réponse de la requête:%s\n", jsonResp)
	return shim.Success(Issueraccountbytes)
}

func main() {
	err := shim.Start(new(TradeChaincode))
	if err != nil {
		fmt.Printf("Erreur en démarrant le Trade chaincode: %s", err)
	}
}

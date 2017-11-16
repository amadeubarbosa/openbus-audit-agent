#!/bin/bash

request=$1

if [ -z "$request" ]; then
  request='{"id":"11123", "solutionCode":"BEEP", "actionName":"exampleMethod", "timestamp":"2017-11-26 12:04:23.222", "userName":"Y9IF", "input": "aXNzbyDDqSB1bSB0ZXN0ZQ==", "resultCode":"true", "output":"aXNzbyDDqSB1bSB0ZXN0ZQ==", "duration":"321", "environment":"TST", "openbusProtocol":"v2_1", "interfaceName":"IDL:dummy:1.0", "loginId":"a7978248-77c7-11e7-89ea-0050569e00ad", "ipOrigin":"10.29.240.182:14428"}'
fi

curl -H "Content-Type: application/json" -X POST -d \'$request\' -u SAUBEEP http://srvintegracaotst.ep.petrobras.com.br/audit-service/api/publish

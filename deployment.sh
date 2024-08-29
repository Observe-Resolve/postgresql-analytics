#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
   --dtoperatortoken)
          DTOPERATORTOKEN="$2"
         shift 2
          ;;
       --dtingesttoken)
          DTTOKEN="$2"
         shift 2
          ;;
       --dturl)
          DTURL="$2"
         shift 2
          ;;
       --clustername)
         CLUSTERNAME="$2"
         shift 2
         ;;
       --posgresqluser)
         USER="$2"
        shift 2
        ;;
       --posgresqlpassword)
       PASSWORD="$2"
       shift 2
       ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
 if [ -z "$CLUSTERNAME" ]; then
   echo "Error: clustername not set!"
   exit 1
 fi
 if [ -z "$DTURL" ]; then
   echo "Error: Dt url not set!"
   exit 1
 fi

 if [ -z "$DTTOKEN" ]; then
   echo "Error: Data ingest api-token not set!"
   exit 1
 fi

 if [ -z "$DTOPERATORTOKEN" ]; then
   echo "Error: DT operator token not set!"
   exit 1
 fi
if [ -z "$USER" ]; then
   echo "Error: posgresqluser not set!"
   exit 1
 fi
 if [ -z "$PASSWORD" ]; then
    echo "Error: posgresqlpassword not set!"
    exit 1
  fi


helm upgrade --install ingress-nginx ingress-nginx  --repo https://kubernetes.github.io/ingress-nginx  --namespace ingress-nginx --create-namespace --set controller.opentelemetry.enabled=true --set controller.metrics.enabled=true \
                                                                                                                                                                                                --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
                                                                                                                                                                                                --set-string controller.podAnnotations."prometheus\.io/port"="10254"
#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
CLUSTERID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}');

#### Deploy the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.0/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.0/kubernetes-csi.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -ojson | jq -j '.status.loadBalancer.ingress[].ip')
   [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP

### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules
sed -i "s,IP_TO_REPLACE,$IP," node-demo/node_deployment.yaml
sed -i "s,IP_TO_REPLACE,$IP," K6/cronjob.yaml
#Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl label namespace  default oneagent=false
kubectl apply -f opentelemetry/rbac.yaml
kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml

kubectl create ns fluentbit
kubectl label namespace  default oneagent=false
kubectl apply -f fluentbit/rbac.yaml -n fluentbit
DT_HOST=$(echo $DTURL | grep -oP 'https://\K\S+')
kubectl create secret generic dynatrace -n fluentbit  --from-literal=clustername="$CLUSTERNAME" --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dynatrace_oltp_host="$DT_HOST" --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl apply -f fluentbit/fluentbit.yaml -n fluentbit
kubectl apply -f  fluentbit/rbac.yaml -n fluentbit
kubectl apply -f fluentbit/fluent.yaml -n fluentbit
kubectl apply -f fluentbit/fluentbitsvc.yaml -n fluentbit

#deploy demo application
kubectl create ns post-demo
kubectl label namespace  post-demo oneagent=false
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL"  --from-literal=dt_api_token="$DTTOKEN" -n post-demo
kubectl -n post-demo  create secret generic postgres-secret --from-literal="POSTGRES_USER=$USER" --from-literal="POSTGRES_PASSWORD=$PASSWORD" --from-literal="POSTGRES_DB=todos"
kubectl apply -f node-demo/init_db.yaml -n post-demo
kubectl apply -n post-demo -f node-demo/posgresql_deploy.yaml
kubectl apply -n post-demo -f node-demo/node_deployment.yaml
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace
PODID=$(kubectl get  pods -l app=nodejsdemo -n post-demo -ojson | jq -j '.items[0].metadata.name')
kubectl exec $PODID -n post-demo knex migrate:latest
kubectl exec $PODID -n post-demo knex seed:run

kubectl apply -f K6/cronjob.yaml -n post-demo
#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "url of the demo: "
echo " post-demo url : http://postddemo.$IP.nip.io"
echo "========================================================"



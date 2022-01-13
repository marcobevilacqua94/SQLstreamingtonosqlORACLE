#!/bin/bash

# adapted from https://github.com/cha87de/couchbase-docker-cloudnative

function retry() {
    for i in $(seq 1 10); do
        $1
	if [[ $? == 0 ]]; then
	    return 0
	fi
	sleep 1
    done
    return 1
}

function bucketCreate(){
    couchbase-cli bucket-create -c localhost -u Administrator -p password \
        --bucket=$BUCKET \
        --bucket-type=couchbase \
        --bucket-ramsize=512 \
        --bucket-replica=1 \
        --wait
    if [[ $? != 0 ]]; then
        return 1
    fi
}

function scopeCreate(){
    couchbase-cli collection-manage --cluster localhost --username Administrator --password password \
        --bucket=$BUCKET \
        --create-scope=$SCOPE 
    if [[ $? != 0 ]]; then
        return 1
    fi
}

function collectionsCreate(){
    for i in $(echo $COLLECTIONS | sed "s/,/ /g"); do
       echo "$i"
        couchbase-cli collection-manage --cluster localhost --username Administrator --password password \
        --bucket=$BUCKET \
        --create-collection=$SCOPE.$i
    done

    if [[ $? != 0 ]]; then
        return 1
    fi
}



function indexCreate(){
    sleep 30
    cmd='CREATE PRIMARY INDEX ON `'$BUCKET'`'
    createOutput=$(cbq -u $USER -p $PASS --script="$cmd")
    if [[ $? != 0 ]]; then
        echo $createOutput >&2
        return 1
    fi
}

function clusterUp(){
    # wait for service to come up
    until $(curl --output /dev/null --silent --head --fail http://localhost:8091); do
        printf '.'
        sleep 1
    done

    # initialize cluster
    initOutput=$(couchbase-cli cluster-init -c localhost \
            --cluster-username=Administrator \
            --cluster-password=password \
            --cluster-port=8091 \
            --services=data,index,query \
            --cluster-ramsize=1024 \
            --cluster-index-ramsize=256 \
            --index-storage-setting=default)
    if [[ $? != 0 ]]; then
        echo $initOutput >&2
        return 1
    fi
}

function main(){
    set -ex
    echo "Couchbase UI :8091"
    echo "Couchbase logs /opt/couchbase/var/lib/couchbase/logs"
    ./entrypoint.sh couchbase-server &
    if [[ $? != 0 ]]; then
        echo "Couchbase startup failed. Exiting." >&2
        exit 1
    fi

    clusterUp
    if [[ $? != 0 ]]; then
        echo "Cluster init failed. Exiting." >&2
        exit 1
    fi

    retry bucketCreate
    if [[ $? != 0 ]]; then
        echo "Bucket create failed. Exiting." >&2
        exit 1
    fi

    retry scopeCreate
    if [[ $? != 0 ]]; then
        echo "Scope create failed. Exiting." >&2
        exit 1
    fi

    retry collectionsCreate
    if [[ $? != 0 ]]; then
        echo "Collection create failed. Exiting." >&2
        exit 1
    fi

    retry indexCreate
    if [[ $? != 0 ]]; then
        echo "Index create failed. Exiting." >&2
        exit 1
    fi

    set +ex

    # entrypoint.sh launches the server but since config.sh is pid 1 we keep it
    # running so that the docker container does not exit.
    wait
}

main
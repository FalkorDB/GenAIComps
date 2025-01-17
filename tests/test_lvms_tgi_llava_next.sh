#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe

WORKPATH=$(dirname "$PWD")
ip_address=$(hostname -I | awk '{print $1}')

function build_docker_images() {
    cd $WORKPATH
    echo $(pwd)
    git clone https://github.com/yuanwu2017/tgi-gaudi.git && cd tgi-gaudi && git checkout v2.0.4
    docker build -t opea/llava-tgi:comps .
    cd ..
    docker build --no-cache -t opea/lvm-tgi:comps -f comps/lvms/Dockerfile_tgi .
}

function start_service() {
    unset http_proxy
    model="llava-hf/llava-v1.6-mistral-7b-hf"
    docker run -d --name="test-comps-lvm-llava-tgi" -e http_proxy=$http_proxy -e https_proxy=$https_proxy -p 8399:80 --runtime=habana -e PT_HPU_ENABLE_LAZY_COLLECTIVES=true -e SKIP_TOKENIZER_IN_TGI=true -e HABANA_VISIBLE_DEVICES=all  -e OMPI_MCA_btl_vader_single_copy_mechanism=none --cap-add=sys_nice --ipc=host opea/llava-tgi:comps --model-id $model --max-input-tokens 4096 --max-total-tokens 8192
    docker run -d --name="test-comps-lvm-tgi" -e LVM_ENDPOINT=http://$ip_address:8399 -e http_proxy=$http_proxy -e https_proxy=$https_proxy -p 9399:9399 --ipc=host opea/lvm-tgi:comps
    sleep 3m
}

function validate_microservice() {
    result=$(http_proxy="" curl http://localhost:9399/v1/lvm -XPOST -d '{"image": "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mP8/5+hnoEIwDiqkL4KAcT9GO0U4BxoAAAAAElFTkSuQmCC", "prompt":"What is this?"}' -H 'Content-Type: application/json')
    if [[ $result == *"yellow"* ]]; then
        echo "Result correct."
    else
        echo "Result wrong."
        exit 1
    fi

}

function stop_docker() {
    cid=$(docker ps -aq --filter "name=test-comps-lvm*")
    if [[ ! -z "$cid" ]]; then docker stop $cid && docker rm $cid && sleep 1s; fi
}

function main() {

    stop_docker

    build_docker_images
    start_service

    validate_microservice

    stop_docker
    echo y | docker system prune

}

main

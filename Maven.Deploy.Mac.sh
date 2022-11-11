#!/bin/sh

mvn install:install-file -Dfile=./src/main/resources/pom.xml -DpomFile=./src/main/resources/pom.xml
mvn deploy:deploy-file   -Dfile=./src/main/resources/pom.xml -DpomFile=./src/main/resources/pom.xml -DrepositoryId=thirdparty -Durl=http://HY-ZhengWei:8081/repository/thirdparty

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    parameters {
        string(name: 'DOCKERHUB_REPO', defaultValue: '', description: 'Docker Hub repository, for example username/giai-dau. Leave blank to build locally without pushing.')
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Tag to publish for builds from main.')
    }

    environment {
        DOCKERHUB_CREDENTIALS = 'hubdocker'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate application') {
            steps {
                script {
                    docker.image('node:22-alpine').inside {
                        sh 'npm ci'
                        sh 'npm run check'
                    }
                }
            }
        }

        stage('Build Docker image') {
            when {
                expression { isMainBranch() }
            }
            steps {
                script {
                    def repo = params.DOCKERHUB_REPO.trim()
                    def tag = params.IMAGE_TAG.trim()
                    if (repo && !(repo ==~ /[a-z0-9]+(?:[._-][a-z0-9]+)*\/[a-z0-9]+(?:[._-][a-z0-9]+)*/)) {
                        error('DOCKERHUB_REPO must use the format username/repository.')
                    }
                    if (repo && !(tag ==~ /[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}/)) {
                        error('IMAGE_TAG contains unsupported characters.')
                    }
                    def imageName = repo ? "${repo}:${tag}" : "giai-dau:${env.BUILD_NUMBER}"
                    env.BUILT_IMAGE = imageName
                    docker.build(imageName, '.')
                }
            }
        }

        stage('Push image to Docker Hub') {
            when {
                expression { isMainBranch() && params.DOCKERHUB_REPO?.trim() }
            }
            steps {
                script {
                    docker.withRegistry('https://index.docker.io/v1/', env.DOCKERHUB_CREDENTIALS) {
                        docker.image(env.BUILT_IMAGE).push()
                    }
                }
            }
        }

        stage('Archive build files') {
            steps {
                archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js,Dockerfile,.dockerignore', fingerprint: true
            }
        }
    }
}

def isMainBranch() {
    def branch = (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').tokenize('/').last()
    return branch == 'main'
}

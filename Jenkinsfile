pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install dependencies') {
            steps {
                bat 'npm ci'
            }
        }

        stage('Validate application') {
            steps {
                bat 'npm run check'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js', fingerprint: true, allowEmptyArchive: true
        }
    }
}

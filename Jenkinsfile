node {
    stage('Checkout') {
        checkout scm
    }

    stage('Install dependencies') {
        bat 'npm ci'
    }

    stage('Validate application') {
        bat 'npm run check'
    }

    stage('Archive build files') {
        archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js', fingerprint: true, allowEmptyArchive: true
    }
}

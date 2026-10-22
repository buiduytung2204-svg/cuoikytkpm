node {
    // Pick up changes from GitHub without exposing the local Jenkins instance.
    properties([pipelineTriggers([pollSCM('H/5 * * * *')])])

    def deployDir = 'C:\\Users\\tungb\\OneDrive\\Tài liệu\\cuoikytkpm-main\\cuoikytkpm-main'

    stage('Checkout') {
        checkout scm
    }

    def sourceBranch = env.BRANCH_NAME ?: env.GIT_BRANCH ?: 'main'
    def branchName = sourceBranch.tokenize('/').last()

    stage('Install dependencies') {
        bat 'npm ci'
    }

    stage('Validate application') {
        bat 'npm run check'
    }

    stage('Archive build files') {
        archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js,scripts/deploy-windows.ps1', fingerprint: true
    }

    if (branchName == 'main') {
        stage('Deploy to Windows host') {
            withEnv(["DEPLOY_DIR=${deployDir}"]) {
                bat 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\\deploy-windows.ps1 -SourceDir "%WORKSPACE%" -DeployDir "%DEPLOY_DIR%"'
            }
        }
    } else {
        echo "Skipping deployment for branch ${sourceBranch}; only main is deployed."
    }
}

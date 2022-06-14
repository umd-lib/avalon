pipeline {
  // Jenkins configuration dependencies
  //
  //   Global Tool Configuration:
  //     Git
  //
  // This configuration utilizes the following Jenkins plugins:
  //
  //   * Warnings Next Generation
  //   * Email Extension Plugin
  //
  // This configuration also expects the following environment variables
  // to be set (typically in /apps/ci/config/env:
  //
  // JENKINS_EMAIL_SUBJECT_PREFIX
  //     The Email subject prefix identifying the server.
  //     Typically "[Jenkins - <HOSTNAME>]" where <HOSTNAME>
  //     is the name of the server, i.e. "[Jenkins - cidev]"
  //
  // JENKINS_DEFAULT_EMAIL_RECIPIENTS
  //     A comma-separated list of email addresses that should
  //    be the default recipients of Jenkins emails.

  agent any

  options {
    // Throttle a declarative pipeline via options
    throttleJobProperty(
        categories: ['throttle_avalon'],
        throttleEnabled: true,
        throttleOption: 'category'
    )

    buildDiscarder(
      logRotator(
        artifactDaysToKeepStr: '',
        artifactNumToKeepStr: '',
        numToKeepStr: '20'))
  }

  environment {
    DEFAULT_RECIPIENTS = "${ \
      sh(returnStdout: true, \
         script: 'echo $JENKINS_DEFAULT_EMAIL_RECIPIENTS').trim() \
    }"

    EMAIL_SUBJECT_PREFIX = "${ \
      sh(returnStdout: true, script: 'echo $JENKINS_EMAIL_SUBJECT_PREFIX').trim() \
    }"

    EMAIL_SUBJECT = "$EMAIL_SUBJECT_PREFIX - " +
                    '$PROJECT_NAME - ' +
                    'GIT_BRANCH_PLACEHOLDER - ' +
                    '$BUILD_STATUS! - ' +
                    "Build # $BUILD_NUMBER"

    EMAIL_CONTENT =
        '''$PROJECT_NAME - GIT_BRANCH_PLACEHOLDER - $BUILD_STATUS! - Build # $BUILD_NUMBER:
           |
           |Check console output at $BUILD_URL to view the results.
           |
           |There were ${TEST_COUNTS,var="fail"} failed tests.
           |
           |There are ${ANALYSIS_ISSUES_COUNT} static analysis issues in this build.
           |
           |There were ${TEST_COUNTS,var="skip"} skipped tests.'''.stripMargin()
  }

  stages {
    stage('initialize') {
      steps {
        script {
          // Retrieve the actual Git branch being built for use in email.
          //
          // For pull requests, the actual Git branch will be in the
          // CHANGE_BRANCH environment variable.
          //
          // For actual branch builds, the CHANGE_BRANCH variable won't exist
          // (and an exception will be thrown) but the branch name will be
          // part of the PROJECT_NAME variable, so it is not needed.

          ACTUAL_GIT_BRANCH = ''

          try {
            ACTUAL_GIT_BRANCH = CHANGE_BRANCH + ' - '
          } catch (groovy.lang.MissingPropertyException mpe) {
            // Do nothing. A branch (as opposed to a pull request) is being
            // built
          }

          // Replace the "GIT_BRANCH_PLACEHOLDER" in email variables
          EMAIL_SUBJECT = EMAIL_SUBJECT.replaceAll('GIT_BRANCH_PLACEHOLDER - ', ACTUAL_GIT_BRANCH )
          EMAIL_CONTENT = EMAIL_CONTENT.replaceAll('GIT_BRANCH_PLACEHOLDER - ', ACTUAL_GIT_BRANCH )
        }
      }
    }

    stage('build') {
      steps {
        sh '''
          # Purge any volumes not in use by a container
          docker system prune --force --volumes

          # Start the Avalon Docker containers for testing
          docker-compose up --build -d test

          # Make sure "docker_init.sh" script has run
          docker-compose exec -T test bash -c "/home/app/avalon/docker_init.sh"
        '''
      }
    }

    stage('test') {
      steps {
        sh '''
          # Run rspec tests, with JUNit-formatted output
          docker-compose exec -T test bash -c "bundle exec rspec --format documentation --format RspecJunitFormatter --out rspec.xml spec/controllers/groups_controller_spec.rb"
        '''
      }
      post {
        always {
          sh '''
            # Stop Avalon Docker containers, using "--volumes" flag to delete
            # all volumes
            docker-compose down --volumes
          '''

          // Process JUnit-formatter test output
          junit 'rspec.xml'
        }
      }
    }

    // stage('static-analysis') {
    //   steps {
    //     sh '''
    //       # Run Rubocop/static analysis tools
    //     '''
    //   }
    //   post {
    //     always {
    //       // Collect static analysis reports
    //     }
    //   }
    // }

    stage('clean-workspace') {
      steps {
        cleanWs()
      }
    }
  }

  post {
    always {
      emailext to: "$DEFAULT_RECIPIENTS",
               subject: "$EMAIL_SUBJECT",
               body: "$EMAIL_CONTENT"
    }
  }
}

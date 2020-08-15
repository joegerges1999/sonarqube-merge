properties = null

pipeline {
   agent {
       label 'jgerges'
   }
   
   parameters {
       string (defaultValue: "", description: "Machine name", name: "machine")
       string (defaultValue:"", description: "User on legacy machine", name: "username")
       password (defaultValue:"", description: "Password for legacy machine", name: "password")
       choice(choices:['sonarqube', 'nexus', 'fitnesse'], description: 'App to merge', name: 'app')          
       string (defaultValue:"", description: "Version of the app", name: "version")
       string (defaultValue: "", description: "Your team name", name: "team")
       string (defaultValue:"", description: "Hostname to run the app on", name: "hostname")
   }

   stages {
      stage ('Getting required files') {
         steps {
            sh 'mkdir /data/${team} /data/${team}/${app} /data/${team}/${app}/documents'
            sh 'git clone https://github.com/joegerges1999/properties.git /data/${team}/${app}/properties'
            script {
               properties = readProperties file: "/data/${team}/${app}/properties/rancher.properties"
            }
            sh 'sshpass -p $password scp ${username}@${machine}:/data/sonar/backups/${app}-\$(echo ${version} | rev | cut -d "-" -f2 | rev).zip /data/${team}/${app}/documents/'
            sh 'git clone https://github.com/joegerges1999/${app}-merge.git /data/${team}/${app}/migration'
         }
       }

      stage('running the merge operation') {
          steps {
              sh 'chmod +x /data/${team}/${app}/migration/merge.sh'
              sh "/data/${team}/${app}/migration/merge.sh ${app} ${team} ${version} ${hostname} $properties.cluster_id $properties.project_id $properties.token"
          }
      }
      stage('cleaning up machine') {
         steps {
             sh 'rm -rf /data/${team}'
         }
      }
    }
}

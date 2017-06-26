@Grab('org.yaml:snakeyaml:1.17')
import org.yaml.snakeyaml.Yaml
Yaml parser = new Yaml()

def site_configuration_path = "nubis/sites.yaml"

def default_name = "nubis-metadata NUBIS_CI_NAME".execute().text.trim()
def default_git_repo = "nubis-metadata NUBIS_GIT_REPO".execute().text.trim()

def sites

try {
  sites = parser.load(readFileFromWorkspace(site_configuration_path))
  println("Setting up multi-site project")
} catch(Exception ex) {
  println("Defaulting to single project ${default_name} because ${ex}");
  sites = [:]
  sites[default_name] = [:]
  sites[default_name]['repo'] = default_git_repo
}

sites.each {
   def site_name = it.key
   def site_config = it.value
   println("Site ${site_name} has repo at ${site_config['repo'] }") 

  freeStyleJob("${site_name}-deployment") {
    description("""
    ##${site_name}
    #WARNING WARNING
    This is a deployment job that can impact production, **use with care**
    """.stripIndent())
    
    parameters {
      stringParam('stack_name', site_name)
      stringParam('owner', 'infra-aws@mozilla.com')
      stringParam('service_name', site_name)
      stringParam('ami','')
      stringParam('key_name', 'nubis')
      choiceParam('environment', ['stage','prod'])
      choiceParam('region', ['us-west-2','us-east-1'])
    }

    wrappers {
        colorizeOutput()
        timestamps()
    }
    
    steps {
      shell('''
        nubis-deploy
      '''.stripIndent())
    }

    scm {
      git{
            remote {
                name('origin')
                url(site_config['repo'])
            }
            branch('master')
        extensions {
          submoduleOption {
            disableSubmodules(false)
            recursiveSubmodules(true)
            trackingSubmodules(false)
            parentCredentials(false)
            timeout(60)
            reference('')
          }
        }
      }
    }
    
    publishers {
        mailer('infra-aws@mozilla.com', true, true)
        slackNotifier {
          notifyAborted(true)
          notifyBackToNormal(true)
          notifyFailure(true)
          notifyNotBuilt(true)
          notifyRegression(true)
          notifyRepeatedFailure(true)
          notifySuccess(true)
          notifyUnstable(true)
          startNotification(true)
          customMessage('Environment:$environment')
          includeCustomMessage(true)
        } 
        naginatorPublisher {
          rerunIfUnstable(false)
          maxSchedule(3)
          checkRegexp(true)
          rerunMatrixPart(false)
          regexpForRerun("This is a bug with Terraform and should be reported as a GitHub Issue")
          delay {
            fixedDelay {
              delay(60)
            }
           }
         }
     }
  }

  freeStyleJob("${site_name}-build") {
    description("${site_name}-build")
    
    wrappers {
        colorizeOutput()
        timestamps()
    }
    
    properties {
      copyArtifactPermissionProperty {
         projectNames("${site_name}-deployment")
      }
    }
    
    scm {
      git{
            remote {
                name('origin')
                url(site_config['repo'])
            }
            branch('master')
        extensions {
          submoduleOption {
            disableSubmodules(false)
            recursiveSubmodules(true)
            trackingSubmodules(false)
            parentCredentials(false)
            timeout(60)
            reference('')
          }
        }
      }
    }
    
    triggers {
        scm("H/15 * * * *")
    }
    
    steps {
      shell('''
        . /etc/profile.d/proxy.sh > /dev/null 2>&1
        consulate kv set nat/admin/config/IptablesAllowTCP "[ 22 ]"
        nubis-builder build --instance-type c3.large --spot
      '''.stripIndent())
      shell('''
        rm -rf artifacts
        mkdir artifacts
      '''.stripIndent())
      shell('''
        if [ -d nubis/terraform ]; then
          rsync -av nubis/terraform artifacts/
        fi
        if [ -d nubis/builder/artifacts ]; then
          mkdir -p artifacts/builder/
          rsync -av nubis/builder/artifacts/ artifacts/builder/
        fi
      '''.stripIndent())      
    }
    
    publishers {
        archiveArtifacts('artifacts/**')
        downstreamParameterized {
            trigger("${site_name}-deployment") {
                condition('UNSTABLE_OR_BETTER')
                parameters {
                    predefinedBuildParameters {
                      properties("environment=stage")
                    }
                }
            }
        }
        mailer('infra-aws@mozilla.com', true, true)
        slackNotifier {
          notifyAborted(true)
          notifyBackToNormal(true)
          notifyFailure(true)
          notifyNotBuilt(true)
          notifyRegression(true)
          notifyRepeatedFailure(true)
          notifySuccess(true)
          notifyUnstable(true)
          startNotification(true)
        }
    }
  }
}

@Grab('org.yaml:snakeyaml:1.17')
import org.yaml.snakeyaml.Yaml
Yaml parser = new Yaml()

def sites = parser.load(readFileFromWorkspace('sites.yaml'))

sites.each {
   def site_name = it.key
   def site_config = it.value
   println("Site ${site_name} has repo at ${site_config['repo'] }") 

  freeStyleJob("test-${site_name}-build") {
    description("${site_name}-build")
    
    wrappers {
        colorizeOutput()
        timestamps()
    }
    
    properties {
      copyArtifactPermissionProperty {
         projectNames("test-${site_name}-deploy")
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
  }
}

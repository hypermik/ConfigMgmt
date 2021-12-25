#Import-Module powershell-yaml -Verbose

class Searcher {

    [System.String]$apiVersion="1.0"
    
    [System.Collections.Hashtable]$yaml
    [System.Object]$teams


    Searcher([System.String]$token, [System.String]$uri) {

        $b64pat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("PAT:$token"))
        $header = @{'Authorization' = "Basic $b64pat" }
        
        [System.String] $text = [System.Text.Encoding]::GetEncoding("utf-8").GetString(
            (Invoke-WebRequest -Method GET -Uri $uri -Headers $header -UseBasicParsing).Content
            )

        [System.String[]]$buffer = $text.Split("`n")
        $content = ""
        foreach ($line in $buffer) { $content += ($line + "`n") }

        $this.yaml = ConvertFrom-Yaml $content  
        $this.teams = $this.yaml.teams
    }

    [System.String[]] GetAllTeamsNames() {
        return $this.teams.name
    }

    [System.Boolean] IdenticalStrings([System.String]$value, [System.String]$user_str) {
        
        return ($value -ieq $user_str)
    }

    [System.Boolean] TeamExists([System.String]$name) {
        foreach( $team in $this.teams ) {
            if($team.name.GetType().name.ToString() -eq 'List`1') {
                foreach( $value in $team.name ) {
                    if( $this.IdenticalStrings($value, $name) ){
                        return $true
                    }        
                }
            } else {
                if( $this.IdenticalStrings($team.name, $name) ) {
                    return $true
                }                    
            }
        }
        return $false
    }

    [System.Collections.Hashtable] GetTeam($name) {
        foreach( $team in $this.teams ) {
            if($team.name.GetType().name.ToString() -eq 'List`1') {
                foreach( $value in $team.name ) {
                    if( $this.IdenticalStrings($value, $name) ){
                        return $team
                    }        
                }
            } else {
                if( $this.IdenticalStrings($team.name, $name) ) {
                    return $team
                }                    
            }
        }
        return $null
    }

    [System.Collections.Hashtable] GetTeamAISDB([System.String]$team_name) {
        $team = $this.GetTeam($team_name) 
        if(
            $team.ContainsKey("config") -and
            $team.config.ContainsKey("DBs")
        ) {
            foreach($DB in $team.config.DBs) {
                if( $this.IdenticalStrings($DB.name, "AISDB") ) {
                    return $DB
                }
            }
        }
        return $null
    }

    [System.Collections.Hashtable] GetServiceNameAISDB([System.String]$service_name) {
        foreach( $team in $this.teams ) {
            if( $null -ne $team.config ) {
                if ( $null -ne $team.config.DBs ) {
                    foreach( $DB in $team.config.DBs ) {
                        if( $this.IdenticalStrings($DB.name, "AISDB") ) {
                            if( $this.IdenticalStrings($DB.service_name, $service_name) ) {
                                return $DB
                            }
                        }
                    }
                }    
            }
        }
        return $null
    }

    [System.Collections.Hashtable] GetServiceNameAISDBApp([System.String]$service_name, [System.String]$app_name) {
        foreach( $team in $this.teams ) {
            if( $null -ne $team.config ) {
                if ( $null -ne $team.config.DBs ) {
                    foreach( $DB in $team.config.DBs ) {
                        if( $this.IdenticalStrings($DB.name, "AISDB") ) {
                            if( $this.IdenticalStrings($DB.service_name, $service_name) ) {
                                foreach ($app in $team.config.Apps) {
                                    if( $this.IdenticalStrings($app.name, $app_name) ) {
                                        return $app
                                    }                                
                                }
                            }
                        }
                    }
                }    
            }
        }
        return $null
    }

    [System.Collections.Hashtable] GetEnvApp([System.String]$environment_name, [System.String]$app_name) {
        foreach( $team in $this.teams ) {
            if( -not [String]::IsNullOrEmpty($team.environment) -and -not [String]::IsNullOrEmpty($team.config) ) {
                if ( $null -ne $team.config.Apps ) {
                    foreach ($app in $team.config.Apps) {
                        if( $this.IdenticalStrings($app.name, $app_name) ) {
                            return $app
                        }                                
                    }
                }    
            }
        }
        return $null
    }

    [System.Collections.Generic.List[System.Object]] GetTeamAISDBSettings([System.String]$team_name) {
        $DB = $this.GetTeamAISDB($team_name)
        if( $null -ne $DB ) {
            return $DB.settings
        }
        return $null
    }

    [System.Collections.Generic.List[System.Object]] GetAllAISDBSetting([System.String]$setting_name) {

        [System.Collections.Generic.List[System.Object]] $query_list = [System.Collections.Generic.List[System.Object]]::new()

        foreach( $team in $this.teams ) {
            if( $null -ne $team.config -and $null -ne $team.config.DBs ) {
                foreach( $DB in $team.config.DBs ) {
					if( 
                        $this.IdenticalStrings($DB.name, "AISDB") -and 
                        $DB.ContainsKey("deployment") -and $DB.deployment.Count -gt 0 -and
                        $DB.ContainsKey("settings")   -and $DB.settings.Count   -gt 0
                    ) {
                        [System.Collections.Hashtable]$query_table = [System.Collections.Hashtable]::new()

                        $query_table.Add("team_name", $team.name)

                        [System.Collections.Hashtable]$AISDB_table = [System.Collections.Hashtable]::new()

                        $AISDB_table.Add("name", $DB.name)
                        $AISDB_table.Add("tns", $DB.tns)
                        $AISDB_table.Add("service_name", $DB.service_name)
                        $AISDB_table.Add("deployment", $DB.deployment)

						foreach( $setting in $DB.settings ) {
							if( $this.IdenticalStrings($setting_name, $setting.name) ) {

								$AISDB_table.Add("settings", $setting)

							}
						}

                        $query_table.Add("DBs", $AISDB_table)
                        $query_list.Add($query_table)
							
					}
                }                
            }
        }
        return $query_list
    }    
    
    [System.Collections.Generic.List[System.Object]] GetInfrastructureAISDB([System.String]$infrastructure_name) {

        [System.Collections.Generic.List[System.Object]] $query_list = [System.Collections.Generic.List[System.Object]]::new()

        foreach( $team in $this.teams ) {
            if( $null -ne $team.config -and $null -ne $team.config.DBs ) {
                foreach( $DB in $team.config.DBs ) {
					if( 
                        $this.IdenticalStrings($DB.name, "AISDB") -and 
                        $DB.ContainsKey("deployment") -and $DB.deployment.Count -gt 0 -and 
                        $this.IdenticalStrings($DB.deployment.infrastructure, $infrastructure_name)
                    ) {
                        [System.Collections.Hashtable]$query_table = [System.Collections.Hashtable]::new()

                        $query_table.Add("team_name", $team.name)
                        $query_table.Add("DBs", $DB)
                        $query_list.Add($query_table)

                    }
                }
            }
        }
        return $query_list
    }
    

    [System.Collections.Hashtable] GetTeamAISDBDeployment([System.String]$team_name) {
        $DB = $this.GetTeamAISDB($team_name)
        if( $null -ne $DB ) {
            return $DB.deployment
        }
        return $null
    }

    [System.Collections.Generic.List[System.Object]] GetServiceNameAISDBSettings([System.String]$service_name) {
        $DB = $this.GetServiceNameAISDB($service_name)
        if( $null -ne $DB ) {
            return $DB.settings
        }
        return $null
    }

    [System.Collections.Hashtable] GetServiceNameAISDBDeployment([System.String]$service_name) {
        $DB = $this.GetServiceNameAISDB($service_name)
        if( $null -ne $DB ) {
            return $DB.deployment
        }
        return $null
    }

    [System.Collections.Hashtable] GetTeamApp([System.String]$team_name, [System.String]$app_name) {
        $apps = $this.GetTeam($team_name).config.apps
        foreach( $app in $apps ) {
            if( $this.IdenticalStrings($app.name, $app_name) ) {
                return $app
            }
        }
        return $null
    }

    [System.Object] GetTeamAppSettings([System.String]$team_name, [System.String]$app_name) {
        if( $this.TeamExists($team_name) ) {
            return $this.GetTeamApp($team_name, $app_name).settings
        }
        return $null
    }

    [System.Object] GetTeamAppDeployment([System.String]$team_name, [System.String]$app_name) {
        if( $this.TeamExists($team_name) ) {
            return $this.GetTeamApp($team_name, $app_name).deployment
        }
        return $null
    }
}

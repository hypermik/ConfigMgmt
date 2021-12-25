<# 
    Класс предназначен для деплоймента в БД oracle
    и подготовки деплоймента в IIS
#>

class Deployer {
    [System.String]$method
    [System.Object]$connection
    [System.String]$infrastructure

    Deployer( 
        [System.String]$method, 
        [System.String]$method_path, 
        [System.String]$username, 
        [System.String]$password, 
        [System.String]$data_source, 
        [System.String]$infrastructure 
    ) {
        $this.method = $method
        $this.infrastructure = $infrastructure

        # Инициализируем подключение к БД
        if( $this.method -ieq "ODP.NET" ) {
            $connection_string = "User Id={0};Password={1};Data Source={2}" -f $username, $password, $data_source
            try {
                Add-Type -LiteralPath  $method_path
                $this.connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connection_string)
                Write-Host( "The connection object for {0} succefully created  using {1}" -f $this.infrastructure, $this.method )
            }
            catch { throw $( "Error occured while initializing {0} object: {1}" -f $this.method, $PSItem.Exception.Message ) }
        }
    }


    <#
        В параметрах передается тэг encrypted_credential, который является зашифрованной json-структорой следующего вида:
        {"username": "someusername", "password": somepassword}
        где: someusername - передаваемое имя пользователя, somepassword - передаваемый пароль 
    #>
    Deployer( 
        [System.String]$method, 
        [System.String]$method_path, 
        [System.String]$encrypted_parts, 
        [System.String]$data_source, 
        [System.String]$infrastructure 
    ) {
        $this.method = $method
        $this.infrastructure = $infrastructure

        # расшифровываем encrypted_credential
        $encrypted_credential = ""
        [System.String[]]$splitted_parts = $encrypted_parts.Split("`n")
        foreach( $part in $splitted_parts ) {
            $encrypted_credential += $part
        }
        Write-Host $encrypted_credential
        $secret = ConvertTo-SecureString $encrypted_credential
        $secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        $jsonStruct = [Runtime.InteropServices.Marshal]::PtrToStringAuto($secretPointer)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)

        $credential = ConvertFrom-Json $jsonStruct

        # Инициализируем подключение к БД
        if( $this.method -ieq "ODP.NET" ) {
            $connection_string = "User Id={0};Password={1};Data Source={2}" -f $credential.username, $credential.password, $data_source
            try {
                Add-Type -LiteralPath  $method_path
                $this.connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connection_string)
                Write-Host( "The connection object for {0} succefully created  using {1}" -f $this.infrastructure, $this.method )
            }
            catch { throw $( "Error occured while initializing {0} object: {1}" -f $this.method, $PSItem.Exception.Message ) }
        }
    }


    Oracle_RunSQLFromScript([System.String]$script_path) {

        if( $this.method -ieq "ODP.NET" ) { 
            [System.String]$script = ""
            try {
                $script = Get-Content -path $script_path -raw
            }
            catch { throw ( "Could not load script from {0} due to error: {1}" -f $script_path, $PSItem.Exception.Message ) }

            Write-Host( "Running script from {0}" -f $script_path )

            $this.ODP_ExecuteNonQuery($script) 
        }
    }


    Oracle_CreateOrChangeAccount([System.String]$username, [System.String]$password) {

        if( $this.method -ieq "ODP.NET" ) { 
            [System.String]$command_text = @"
            declare
            userexist integer;
            begin
            select count(*) into userexist from dba_users where username='$username';
            if (userexist = 0) then
                execute immediate 'create user $username identified by $password';
            else
                execute immediate 'alter user $username identified by $password';
            end if;
            end;
"@
            $this.ODP_ExecuteNonQuery($command_text) 
        }
    }


    Oracle_GrantDeveloperRole([System.String]$username) {

        if( $this.method -ieq "ODP.NET" ) { 
            [System.String[]]$grant_set = @(
                "grant create session to $username"
                "grant connect to $username"
                "grant SELECT ANY TABLE to $username"
                "grant INSERT ANY TABLE to $username"
                "grant update ANY TABLE to $username"
                "grant delete ANY TABLE to $username"
                "GRANT execute any class to $username"
                "GRANT execute on dbms_lock to $username"
                "GRANT execute on dbms_monitor to $username"
                "GRANT execute on dbms_result_cache to $username"
                "GRANT execute on SYS.UTL_RECOMP to $username"
                "grant create any index to $username"
                "grant create any table to $username"
                "GRANT create ANY VIEW TO $username"
                "grant CREATE ANY PROCEDURE TO $username"
                "grant ALTER ANY PROCEDURE to $username"
                "grant ALTER ANY TABLE to $username"
                "grant ALTER ANY MATERIALIZED VIEW to $username"
                "grant execute any procedure to $username"
            )
            $this.ODP_ExecuteNonQuery($grant_set) 
        }
    }


    Oracle_SetSequences([System.Int16] $node) {

        if( $this.method -ieq "ODP.NET" ) { 
            [System.String]$command_text = @"
            begin
            execute immediate 'alter trigger AIS.HISTPARM_BIU disable';
            execute immediate 'update ais.histparm set node = $node where isn = 490';
            execute immediate 'alter trigger AIS.HISTPARM_BIU enable';
            execute immediate 'update ais.histnode set ISN = $node where parentisn = 3';
            replicais.set_Sequence_mask;
            end;

"@        
            $this.ODP_ExecuteNonQuery($command_text) 
        }
    }


    Oracle_SetSequences() {

        if( $this.method -ieq "ODP.NET" ) { 
            [System.String[]]$command_text = @( 
                
                "Alter Trigger ais.histparm_biu Disable",

                @"
                Declare
                    v    Number;
                Begin
                    Select  isn
                        Into  v
                        From  histnode
                        Where  fullname = SYS_CONTEXT ('USERENV', 'DB_NAME');
                
                    Update  ais.histparm
                        Set  node   = v -- нода соответствует прописанной на маске
                        Where  isn = 490;
                
                    Commit;
                    
                    Dbms_Output.put_line ('01:update histparm = OK');
                    Exception
                    When Others
                    Then
                        Rollback;
                        Dbms_Output.put_line ('01:update ER:' || SQLERRM);
                        Return;
                End;
"@,
                
                "alter trigger AIS.HISTPARM_BIU enable",

                @"
                Begin
                    replicais.set_sequence_mask;
                    Dbms_Output.put_line ('01:Set_Sequence_mask = OK');
                    Exception
                    When Others
                    Then
                        Rollback;
                        Dbms_Output.put_line ('02:SetMask ER:' || SQLERRM);
                        Return;
                End;

"@,
                "Alter Trigger replicais.nrepplic_sender_settings_aui Disable",

                @"
                Begin
                    delete replicais.nreplic_sender_settings;
                    delete replicais.added_replication;
                    Insert  All
                    When 1 = 1
                    Then
                        Into  replicais.nreplic_sender_settings (owner, table_name, node, stoped, r_type)
                        Values  (
                                    owner, table_name, parentisn, stoped, r_type)
                --    When 1 = 1
                --    Then
                --        Into  replicais.added_replication (isn, node, shortname, owner, table_name)
                --          Values  (rn, parentisn, Null, owner, table_name)
                        Select  ROWNUM rn
                            , UPPER (SUBSTR (COLUMN_VALUE, 1, INSTR (COLUMN_VALUE, '.') - 1)) owner
                            , UPPER (SUBSTR (COLUMN_VALUE, INSTR (COLUMN_VALUE, '.') + 1)) table_name
                            , h.parentisn
                            , 'N' stoped
                            , 'I' r_type
                        From  Table (ais.str2tblc (REPLACE ('aisws.svcl_application,
                    aisws.svcl_user,
                    ais.subphone_t,
                    ais.subject_t,
                    ais.subhuman_t,
                    ais.WSUserLKAccount', CHR (10), ''))) t Join histnode h On h.isn = hist.node; --для тестов сделано для 31

                    Commit;
                End;
"@,
            "Alter Trigger replicais.nrepplic_sender_settings_aui Enable",

            @"
            declare
                v_start_date timestamp;
            BEGIN
                select j.START_DATE into v_start_date from DBA_SCHEDULER_JOBS j where owner = 'REPLICAIS' and job_name = 'JOB_HISTLOG_BY_ISN_P1';
                SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
                ( name => 'REPLICAIS.JOB_HISTLOG_BY_ISN_P1'
                ,attribute => 'START_DATE'
                ,value => v_start_date+numtodsinterval( hist.node, 'SECOND')
                );
            END;
"@
            )
            $this.ODP_ExecuteNonQuery($command_text) 
        }
    }


    hidden ODP_ExecuteNonQuery([System.String]$command_text) {

        if( [System.String]::IsNullOrEmpty($command_text) ) { Write-Warning "Empty command text!"; break }

        if( $null -eq $this.connection ) { throw $( "Connection of method {0} is not initialized!" -f $this.method ) }

        $cmd = $null

        try {
            $this.connection.Open()
            $cmd = $this.connection.CreateCommand()
            $cmd.CommandText = $command_text
            $cmd.ExecuteNonQuery()
            $cmd.Dispose()
            $this.connection.Close()
        }
        catch {
            if( $null -ne $cmd ) {$cmd.Dispose()}
            if( $this.connection.State -ieq "Open" ) {$this.connection.Close()}
            Write-Warning( "Some errors occured while executing an Oracle command: {0}" -f $PSItem.Exception.Message )
        }
    }


    hidden ODP_ExecuteNonQuery([System.String[]]$command_set) {

        if( $null -eq $command_set ) { Write-Warning "Empty command set!"; break }

        if( $null -eq $this.connection ) { throw $( "Connection of method {0} is not initialized!" -f $this.method ) }

        $cmd = $null

        try {
            $this.connection.Open()
            $cmd = $this.connection.CreateCommand()        
            foreach( $command in $command_set ) {
                $cmd.CommandText = $command
                $cmd.ExecuteNonQuery()
            }
            $cmd.Dispose()
            $this.connection.Close()
        }
        catch {
            if( $null -ne $cmd ) {$cmd.Dispose()}
            if( $this.connection.State -ieq "Open" ) {$this.connection.Close()}
            Write-Warning( "Some errors occured while executing an Oracle command: {0}" -f $PSItem.Exception.Message )
        }
    }


    hidden [Object] ODP_ExecuteReader([System.String]$command_text) {

        if( [System.String]::IsNullOrEmpty($command_text) ) { Write-Warning "Empty command text!"; break }

        if( $null -eq $this.connection ) { throw $( "Connection of method {0} is not initialized!" -f $this.method ) }

        $cmd = $null
        $reader = $null

        try {
            $this.connection.Open()
            $cmd = $this.connection.CreateCommand()
            $cmd.CommandText = $command_text
            $reader = $cmd.ExecuteReader()
            $cmd.Dispose()
            $this.connection.Close()
        }
        catch {
            if( $null -ne $cmd ) {$cmd.Dispose()}
            if( $this.connection.State -ieq "Open" ) {$this.connection.Close()}
            Write-Warning( "Some errors occured while executing an Oracle command: {0}" -f $PSItem.Exception.Message )
        }
        return $reader
    }
}

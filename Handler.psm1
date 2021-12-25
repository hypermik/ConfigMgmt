Using module .\Deployer.psm1

Using namespace System
Using namespace System.IO
Using namespace System.Xml
Using namespace System.Xml.XPath
Using namespace System.Collections

## Team Settings Handler

<#
    Класс обработки тэгов из файла конфигураций
#>

class Handler {

    [Deployer]$deployer = $null
    [XmlDocument]$WebConfig = $null
    [System.String]$DBPass

    Handler() {
    }

    Handler([String]$WebConfigString) {
        $this.WebConfig = [XmlDocument]::new()
        $this.WebConfig.LoadXml($WebConfigString)
    }


    <# обработчик yaml-тэгов БД АИС
    #>
    ApplyAISDBSettings([System.Collections.Hashtable]$AISDB) {
        
        if ( 
            $AISDB.ContainsKey("tns")        -and 
            $AISDB.ContainsKey("deployment") -and $AISDB.deployment.Count -gt 0 -and
            $AISDB.ContainsKey("settings")   -and $AISDB.settings.Count   -gt 0      ) {

                if( -not ([System.String]::IsNullOrEmpty($AISDB.deployment.username) -and ([System.String]::IsNullOrEmpty($AISDB.deployment.password)) -or [System.String]::IsNullOrEmpty($this.DBPass)) ) {
                    $this.deployer = [Deployer]::new(
                        $AISDB.deployment.method,
                        $AISDB.deployment.method_path,
                        $AISDB.deployment.username,
                        $($AISDB.deployment.password ?? $this.DBPass),
                        $AISDB.tns,
                        $AISDB.deployment.infrastructure
                    )        
                }

                if( $AISDB.deployment.ContainsKey("encrypted_credential") -and -not [System.String]::IsNullOrEmpty($AISDB.deployment.encrypted_credential) ) {
                    $this.deployer = [Deployer]::new(
                        $AISDB.deployment.method,
                        $AISDB.deployment.method_path,
                        $AISDB.deployment.encrypted_credential,
                        $AISDB.tns,
                        $AISDB.deployment.infrastructure
                    )        
                }

            [System.String]$setting_name = $null
            foreach ($setting in $AISDB.settings) {

                $setting_name = $setting["name"]
                Write-Host $( "Setting is getting applied: {0}..." -f $setting_name )

                $enum = $setting.GetEnumerator()
        
                while( $enum.MoveNext() ) {
        
                    switch( $enum.Current.Key ) {

                        "script" {

                            $value = $enum.Current.Value
                            if( $value.ContainsKey("file_path") ) {
                                $this.deployer.Oracle_RunSQLFromScript($value["file_path"])         
                            }
                            Break
                        }

                        "account" {

                            $value = $enum.Current.Value
                            if( $value.ContainsKey("username") -and $value.ContainsKey("password") ) {
                                $this.deployer.Oracle_CreateOrChangeAccount($value["username"], $value["password"])
                            }
                            if( $value.ContainsKey("role") ) {
                                
                                switch( $value["role"] ){

                                    "developer" {
                                        $this.deployer.Oracle_GrantDeveloperRole($value["username"])
                                        Break
                                    }
                                }
                            }
                            Break
                        }

                        "sequence_node" {
                            $value = $enum.Current.Value
                            if( -not [System.String]::IsNullOrEmpty($value) ) {
                                if( $value -is [System.String] -and $value -ieq "auto" ) {
                                    $this.deployer.Oracle_SetSequences()
                                }
                                if( $value -is [Int16] ) {
                                    $this.deployer.Oracle_SetSequences($value)
                                }
                                
                            }
                        }

                        "name" { Break }
                            
                        Default {
                            Write-Warning $( "Unhandled key found: {0}" -f $enum.Current.Key )
                        }
                    }
                }
            }
            $this.deployer.connection.Dispose()
        } 
        else { Write-Host( "Settings and Deployment were not found for Service Name {0}" -f $AISDB.service_name )}        
    }


    <# обработчик yaml-тегов ASP.Net приложений
    #>
    ApplyASPNETAppSettings([Hashtable]$App) {

        if( $App.ContainsKey("settings") -and $App.settings.Count -gt 0 ) {

            [System.String]$setting_name = $null

            foreach ($setting in $App.settings) {

                $setting_name = $setting["name"]
                Write-Host $( "Applying setting {0}..." -f $setting_name )

                $enum = $setting.GetEnumerator()

                while( $enum.MoveNext() ) {

                    switch ( $enum.Current.Key ) {

                        "name" {

                            Break
                        }

                        "webconfig_map" {

                            if( $null -ne $this.WebConfig ) {

                                $this.WebConfigTransformer( $enum.Current.Value )
                            }
                            else { Write-Warning "webconfig_map requires WebConfig for transformaion!" }
                            Break

                        }

                        Default {
                            Write-Warning $( "Unhandled key found: {0}" -f $enum.Current.Key )
                        }
                    }
                }
            }
        }
    }


    <# копирует заданные в webconfig_map атрибуты в Web.Config
    #>
    hidden GetNodeAttributes([XPathNavigator]$patchNav, [Stack]$xpath, [XPathNavigator]$webConfigNav) {

        $keyAttribute = ""
        $attributes = [Hashtable]::new()
        $null = $patchNav.MoveToFirstAttribute()
        if( $patchNav.Name -ieq "name" -or $patchNav.Name -ieq "key" ) { $keyAttribute = $patchNav.Name }
        $attributes.Add($patchNav.Name, $patchNav.Value)
        while ( $patchNav.MoveToNextAttribute() ) {
            if( $patchNav.Name -ieq "name" -or $patchNav.Name -ieq "key" ) { $keyAttribute = $patchNav.Name }
            $attributes.Add($patchNav.Name, $patchNav.Value)
        }
        $null = $patchNav.MoveToParent()
        
        # выполняем поиск секции исходного Web.Config, в котором 
        # д.б. произведены изменения
        $selection = $webConfigNav.Select( $this.GetXPathStr($xpath) )

        # если секция найдена, начинаем цикл изменения Web.Config
        while( $selection.MoveNext() ) {
            $node = $selection.Current

            # если найдено совпадение по ключевому атрибуту (name или key),
            # то сохраняем значения атрибутов из webconfig_map в Web.Config
            if( $node.GetAttribute($keyAttribute, "") -ieq $attributes[ $keyAttribute ] ) {

                if( $node.MoveToFirstAttribute() ) {
                    $node.SetValue( $attributes[ $node.Name ] )
                    Write-Host $("Updated attribute {0} in tag {1}" -f $node.Name, $( $this.GetXPathStr($xpath).Expression ))    
                }
                while( $node.MoveToNextAttribute() ) {
                    $node.SetValue( $attributes[ $node.Name ] )
                    Write-Host $("Updated attribute {0} in tag {1}" -f $node.Name, $( $this.GetXPathStr($xpath).Expression ))
                }
            }
        }
        # удаляем атрибуты
        Remove-Variable -Name attributes
        
    }


    <# копирует заданный в webconfig_map текст тэгов в Web.Config
    #>
    hidden GetNodeText([XPathNavigator]$patchNav, [Stack]$xpath, [XPathNavigator]$webConfigNav) {

        # поднимаемся до предыдущего тэга в webconfig_map
        $null = $patchNav.MoveToParent()
        $null = $xpath.Pop()
        $null = $patchNav.MoveToParent()
        $null = $xpath.Pop()

        # выполняем поиск секции исходного Web.Config, в котором 
        # д.б. произведены изменения
        $selection = $webConfigNav.Select( $($this.GetXPathStr($xpath)) )

        # выравниваем положение навигатора в исхдном Web.Config и webconfig_map
        while ($selection.MoveNext()) {
            $node = $selection.Current
            $null = $node.MoveToFirstChild()
            $null = $patchNav.MoveToFirstChild()
            $xpath.Push($patchNav.Name)

            # Начинаем цикл копирования изменений из webconfig_map в Web.Config 
            # условия обработки:
            # <tagname /> - значение будет удалено
            # <tagname>new value</tagname> - замена на новое значение

            if( $node.Name -ieq $patchNav.Name ){
                if( $patchNav.IsEmptyElement ) {
                    $node.UnderlyingObject.IsEmpty = $true
                    Write-Host $("Text was deleted in tag {0}" -f $( $this.GetXPathStr($xpath).Expression ))
                }
                else {
                    $node.SetValue($patchNav.Value)
                    Write-Host $("Text was updated in tag {0}" -f $( $this.GetXPathStr($xpath).Expression ))
                }
            }

            while($node.MoveToNext() -and $patchNav.MoveToNext()) {
                $null = $xpath.Pop()
                $xpath.Push($patchNav.Name)

                if( $node.Name -ieq $patchNav.Name ){
                    if( $patchNav.IsEmptyElement ) {
                        $node.UnderlyingObject.IsEmpty = $true
                        Write-Host $("Text was deleted in tag {0}" -f $( $this.GetXPathStr($xpath).Expression ))
                    }
                    else {
                        $node.SetValue($patchNav.Value)
                        Write-Host $("Text was updated in tag {0}" -f $( $this.GetXPathStr($xpath).Expression ))
                    }
                }
            }        
        }
        if($patchNav.MoveToFirstChild()) {$xpath.Push($patchNav.Name)}
    }
  

    <# возвращает стек тэгов как строку XPath
    #>
    hidden [XPathExpression] GetXPathStr([Stack]$xpath) {

        [String[]]$stack_values = $xpath.ToArray()
        [array]::Reverse($stack_values)
        if( $stack_values.Count -eq 0 ) { return "/" } else { $str="" }
        foreach( $value in $stack_values ) {
            if([String]::IsNullOrEmpty($value) ) {continue}
            $str += $( "/{0}" -f $value )
        }
        $res = [XPathExpression]::Compile( $str )
        return $res
    }
    

    <# Трансформатор Web.Config
       Записывает в Web.Config значения атрибутов тэгов из xml-документа, найденного в yaml-теге
       webconfig_map. 
    #>
    hidden WebConfigTransformer([String]$webconfig_map) {
        
        # загружаем содержимое webconfig_map в xml-навигатор
        $patchNav = [XPathDocument]::new( [StringReader]::new($webconfig_map) ).CreateNavigator()

        # загружаем исходный Web.Config в xml-навигатор
        $webConfigNav = $this.WebConfig.CreateNavigator()

        # инициализируем стек тэгов для контроля перемещения по webconfig_map
        [Stack]$xpath= [Stack]::new()
        $patchNav.MoveToRoot()
        
        Write-Host "Web.config transformation is getting started..."
        # начинаем цикл поиска настроек по webconfig_map
        do {
            while( $patchNav.MoveToFirstChild() ) {
                $xpath.Push($patchNav.Name)
                # найдены атрибуты в webconfig_map
                if( $patchNav.HasAttributes ) {
                        $this.GetNodeAttributes($patchNav, $xpath, $webConfigNav)
                    }
                # найдены значения тэгов в webconfig_map
                if( $patchNav.nodeType -ieq "Text" ) {
                        $this.GetNodeText($patchNav, $xpath, $webConfigNav)
                    }
            }

            # продолжаем движение по webconfig_map

            while( -not $patchNav.MoveToNext() -and $xpath.Count -gt 0 ) {
                if( $patchNav.MoveToParent() ) { $null=$xpath.Pop() }
            }

            if( $xpath.Count -gt 0 ) {
                $null = $xpath.Pop()
                $xpath.Push($patchNav.Name)

                # найдены атрибуты в webconfig_map
                if( $patchNav.HasAttributes ) {
                    $this.GetNodeAttributes($patchNav, $xpath, $webConfigNav)
                }

                # найдены значения тэгов в webconfig_map
                if( $patchNav.nodeType -ieq "Text" ) {
                    $this.GetNodeText($patchNav, $xpath, $webConfigNav)
                }

            }                
            # дошли до конца webconfig_map
        }
        while( $xpath.Count -gt 0 )

        Write-Host "Web.config transformation complited."              
    }
}

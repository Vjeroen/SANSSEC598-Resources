param location string = resourceGroup().location
@description('The name for the LogicAPP')
param workflows_SEC598_Secrets_name string = 'SEC598-Secrets'
@description('The name for the workspace')
param workspaces_SEC598_Workspace_name string = 'SEC598-Workspace'
@description('The name for the Sentinel Solution on top of the workspace')
param solutions_SecurityInsights_sec598_workspace_name string = 'SecurityInsights(sec598-workspace)'
@description('optional: The exact ID for the Sentinel API connection')
param connections_azuresentinel_SEC598_Secrets_externalid string = '${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azuresentinelazuresentinel-SEC598-Secrets'
@description('optional: The exact ID for the Sentinel API connection')
param connections_office365_externalid string = '${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azuresentinel'

resource workflows_SEC598_Secrets_name_resource 'Microsoft.Logic/workflows@2017-07-01' = {
  name: workflows_SEC598_Secrets_name
  location: 'eastus'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        'Mail adres to': {
          defaultValue: 'info@sec598.com'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        For_each: {
          foreach: '@triggerBody()?[\'object\']?[\'properties\']?[\'Alerts\']'
          actions: {
            Parse_addeditional_values_in_incident: {
              type: 'ParseJson'
              inputs: {
                content: '@items(\'For_each\')?[\'properties\']?[\'additionalData\']?[\'Custom Details\']'
                schema: {
                  type: 'object'
                  properties: {
                    ApplicationName: {
                      type: 'array'
                      items: {
                        type: 'string'
                      }
                    }
                    TimeGenerated: {
                      type: 'array'
                      items: {
                        type: 'string'
                      }
                    }
                    ActivityDisplayName: {
                      type: 'array'
                      items: {
                        type: 'string'
                      }
                    }
                    Property: {
                      type: 'array'
                      items: {
                        type: 'string'
                      }
                    }
                  }
                }
              }
            }
            Send_approval_Mail_to_Contact_Person_for_change: {
              runAfter: {
                Parse_addeditional_values_in_incident: [
                  'Succeeded'
                ]
              }
              type: 'ApiConnectionWebhook'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
                  }
                }
                body: {
                  NotificationUrl: '@{listCallbackUrl()}'
                  Message: {
                    To: 'jeroen@agron.be'
                    Body: 'You received an approval request for @{body(\'Parse_addeditional_values_in_incident\')?[\'ApplicationName\']} on @{body(\'Parse_addeditional_values_in_incident\')?[\'TimeGenerated\']} \n<br /> \nFull details of the Alert below: \n<br /> \n@{body(\'Parse_addeditional_values_in_incident\')?[\'Property\']}\n<br />'
                    Importance: 'Normal'
                    HideHTMLMessage: false
                    ShowHTMLConfirmationDialog: false
                    Subject: 'Approval Request-@{body(\'Parse_addeditional_values_in_incident\')?[\'ActivityDisplayName\'] } - @{body(\'Parse_addeditional_values_in_incident\')?[\'ApplicationName\']}'
                    Options: 'Approve, Reject'
                  }
                }
                path: '/approvalmail/$subscriptions'
              }
            }
            Condition: {
              actions: {
                'Add_comment_to_incident_(V3)': {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: {
                      incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                      message: '<p>The application @{body(\'Parse_addeditional_values_in_incident\')?[\'ApplicationName\']} is approved!</p>'
                    }
                    path: '/Incidents/Comment'
                  }
                }
              }
              runAfter: {
                Send_approval_Mail_to_Contact_Person_for_change: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  'Send_an_email_(V2)': {
                    type: 'ApiConnection'
                    inputs: {
                      host: {
                        connection: {
                          name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
                        }
                      }
                      method: 'post'
                      body: {
                        To: 'info@sec598.com'
                        Subject: 'Application Update - Rejected'
                        Body: '<p>Request for @{body(\'Parse_addeditional_values_in_incident\')?[\'ApplicationName\'] } is Rejected!</p>'
                        Importance: 'Normal'
                      }
                      path: '/v2/Mail'
                    }
                  }
                }
              }
              expression: {
                and: [
                  {
                    equals: [
                      '@body(\'Send_approval_Mail_to_Contact_Person_for_change\')?[\'SelectedOption\']'
                      'Approve'
                    ]
                  }
                ]
              }
              type: 'If'
            }
          }
          runAfter: {}
          type: 'Foreach'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            id: '${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azuresentinel'
            connectionId: connections_azuresentinel_SEC598_Secrets_externalid
            connectionName: 'azuresentinel-${workflows_SEC598_Secrets_name}'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          office365: {
            id: '${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azuresentinel/managedApis/office365'
            connectionId: connections_office365_externalid
            connectionName: 'office365'
          }
        }
      }
    }
  }
}

resource workspaces_SEC598_Workspace_name_resource 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaces_SEC598_Workspace_name
  location: location
  tags: {
    SANS: 'SEC598'
  }
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_General_AlphabeticallySortedComputers 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_General|AlphabeticallySortedComputers'
  properties: {
    displayName: 'All Computers with their most recent data'
    category: 'General Exploration'
    query: 'search not(ObjectName == "Advisor Metrics" or ObjectName == "ManagedSpace") | summarize AggregatedValue = max(TimeGenerated) by Computer | limit 500000 | sort by Computer asc\r\n// Oql: NOT(ObjectName="Advisor Metrics" OR ObjectName=ManagedSpace) | measure max(TimeGenerated) by Computer | top 500000 | Sort Computer // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_General_dataPointsPerManagementGroup 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_General|dataPointsPerManagementGroup'
  properties: {
    displayName: 'Which Management Group is generating the most data points?'
    category: 'General Exploration'
    query: 'search * | summarize AggregatedValue = count() by ManagementGroupName\r\n// Oql: * | Measure count() by ManagementGroupName // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_General_dataTypeDistribution 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_General|dataTypeDistribution'
  properties: {
    displayName: 'Distribution of data Types'
    category: 'General Exploration'
    query: 'search * | extend Type = $table | summarize AggregatedValue = count() by Type\r\n// Oql: * | Measure count() by Type // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_General_StaleComputers 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_General|StaleComputers'
  properties: {
    displayName: 'Stale Computers (data older than 24 hours)'
    category: 'General Exploration'
    query: 'search not(ObjectName == "Advisor Metrics" or ObjectName == "ManagedSpace") | summarize lastdata = max(TimeGenerated) by Computer | limit 500000 | where lastdata < ago(24h)\r\n// Oql: NOT(ObjectName="Advisor Metrics" OR ObjectName=ManagedSpace) | measure max(TimeGenerated) as lastdata by Computer | top 500000 | where lastdata < NOW-24HOURS // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AllEvents 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AllEvents'
  properties: {
    displayName: 'All Events'
    category: 'Log Management'
    query: 'Event | sort by TimeGenerated desc\r\n// Oql: Type=Event // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AllSyslog 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AllSyslog'
  properties: {
    displayName: 'All Syslogs'
    category: 'Log Management'
    query: 'Syslog | sort by TimeGenerated desc\r\n// Oql: Type=Syslog // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AllSyslogByFacility 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AllSyslogByFacility'
  properties: {
    displayName: 'All Syslog Records grouped by Facility'
    category: 'Log Management'
    query: 'Syslog | summarize AggregatedValue = count() by Facility\r\n// Oql: Type=Syslog | Measure count() by Facility // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AllSyslogByProcess 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AllSyslogByProcessName'
  properties: {
    displayName: 'All Syslog Records grouped by ProcessName'
    category: 'Log Management'
    query: 'Syslog | summarize AggregatedValue = count() by ProcessName\r\n// Oql: Type=Syslog | Measure count() by ProcessName // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AllSyslogsWithErrors 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AllSyslogsWithErrors'
  properties: {
    displayName: 'All Syslog Records with Errors'
    category: 'Log Management'
    query: 'Syslog | where SeverityLevel == "error" | sort by TimeGenerated desc\r\n// Oql: Type=Syslog SeverityLevel=error // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AverageHTTPRequestTimeByClientIPAddress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AverageHTTPRequestTimeByClientIPAddress'
  properties: {
    displayName: 'Average HTTP Request time by Client IP Address'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = avg(TimeTaken) by cIP\r\n// Oql: Type=W3CIISLog | Measure Avg(TimeTaken) by cIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_AverageHTTPRequestTimeHTTPMethod 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|AverageHTTPRequestTimeHTTPMethod'
  properties: {
    displayName: 'Average HTTP Request time by HTTP Method'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = avg(TimeTaken) by csMethod\r\n// Oql: Type=W3CIISLog | Measure Avg(TimeTaken) by csMethod // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountIISLogEntriesClientIPAddress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountIISLogEntriesClientIPAddress'
  properties: {
    displayName: 'Count of IIS Log Entries by Client IP Address'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by cIP\r\n// Oql: Type=W3CIISLog | Measure count() by cIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountIISLogEntriesHTTPRequestMethod 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountIISLogEntriesHTTPRequestMethod'
  properties: {
    displayName: 'Count of IIS Log Entries by HTTP Request Method'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csMethod\r\n// Oql: Type=W3CIISLog | Measure count() by csMethod // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountIISLogEntriesHTTPUserAgent 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountIISLogEntriesHTTPUserAgent'
  properties: {
    displayName: 'Count of IIS Log Entries by HTTP User Agent'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csUserAgent\r\n// Oql: Type=W3CIISLog | Measure count() by csUserAgent // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountOfIISLogEntriesByHostRequestedByClient 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountOfIISLogEntriesByHostRequestedByClient'
  properties: {
    displayName: 'Count of IIS Log Entries by Host requested by client'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csHost\r\n// Oql: Type=W3CIISLog | Measure count() by csHost // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountOfIISLogEntriesByURLForHost 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountOfIISLogEntriesByURLForHost'
  properties: {
    displayName: 'Count of IIS Log Entries by URL for the host "www.contoso.com" (replace with your own)'
    category: 'Log Management'
    query: 'search csHost == "www.contoso.com" | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csUriStem\r\n// Oql: Type=W3CIISLog csHost="www.contoso.com" | Measure count() by csUriStem // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountOfIISLogEntriesByURLRequestedByClient 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountOfIISLogEntriesByURLRequestedByClient'
  properties: {
    displayName: 'Count of IIS Log Entries by URL requested by client (without query strings)'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csUriStem\r\n// Oql: Type=W3CIISLog | Measure count() by csUriStem // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_CountOfWarningEvents 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|CountOfWarningEvents'
  properties: {
    displayName: 'Count of Events with level "Warning" grouped by Event ID'
    category: 'Log Management'
    query: 'Event | where EventLevelName == "warning" | summarize AggregatedValue = count() by EventID\r\n// Oql: Type=Event EventLevelName=warning | Measure count() by EventID // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_DisplayBreakdownRespondCodes 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|DisplayBreakdownRespondCodes'
  properties: {
    displayName: 'Shows breakdown of response codes'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by scStatus\r\n// Oql: Type=W3CIISLog | Measure count() by scStatus // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_EventsByEventLog 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|EventsByEventLog'
  properties: {
    displayName: 'Count of Events grouped by Event Log'
    category: 'Log Management'
    query: 'Event | summarize AggregatedValue = count() by EventLog\r\n// Oql: Type=Event | Measure count() by EventLog // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_EventsByEventsID 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|EventsByEventsID'
  properties: {
    displayName: 'Count of Events grouped by Event ID'
    category: 'Log Management'
    query: 'Event | summarize AggregatedValue = count() by EventID\r\n// Oql: Type=Event | Measure count() by EventID // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_EventsByEventSource 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|EventsByEventSource'
  properties: {
    displayName: 'Count of Events grouped by Event Source'
    category: 'Log Management'
    query: 'Event | summarize AggregatedValue = count() by Source\r\n// Oql: Type=Event | Measure count() by Source // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_EventsInOMBetween2000to3000 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|EventsInOMBetween2000to3000'
  properties: {
    displayName: 'Events in the Operations Manager Event Log whose Event ID is in the range between 2000 and 3000'
    category: 'Log Management'
    query: 'Event | where EventLog == "Operations Manager" and EventID >= 2000 and EventID <= 3000 | sort by TimeGenerated desc\r\n// Oql: Type=Event EventLog="Operations Manager" EventID:[2000..3000] // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_EventsWithStartedinEventID 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|EventsWithStartedinEventID'
  properties: {
    displayName: 'Count of Events containing the word "started" grouped by EventID'
    category: 'Log Management'
    query: 'search in (Event) "started" | summarize AggregatedValue = count() by EventID\r\n// Oql: Type=Event "started" | Measure count() by EventID // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_FindMaximumTimeTakenForEachPage 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|FindMaximumTimeTakenForEachPage'
  properties: {
    displayName: 'Find the maximum time taken for each page'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = max(TimeTaken) by csUriStem\r\n// Oql: Type=W3CIISLog | Measure Max(TimeTaken) by csUriStem // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_IISLogEntriesForClientIP 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|IISLogEntriesForClientIP'
  properties: {
    displayName: 'IIS Log Entries for a specific client IP Address (replace with your own)'
    category: 'Log Management'
    query: 'search cIP == "192.168.0.1" | extend Type = $table | where Type == W3CIISLog | sort by TimeGenerated desc | project csUriStem, scBytes, csBytes, TimeTaken, scStatus\r\n// Oql: Type=W3CIISLog cIP="192.168.0.1" | Select csUriStem,scBytes,csBytes,TimeTaken,scStatus // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_ListAllIISLogEntries 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|ListAllIISLogEntries'
  properties: {
    displayName: 'All IIS Log Entries'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | sort by TimeGenerated desc\r\n// Oql: Type=W3CIISLog // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_NoOfConnectionsToOMSDKService 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|NoOfConnectionsToOMSDKService'
  properties: {
    displayName: 'How many connections to Operations Manager\'s SDK service by day'
    category: 'Log Management'
    query: 'Event | where EventID == 26328 and EventLog == "Operations Manager" | summarize AggregatedValue = count() by bin(TimeGenerated, 1d) | sort by TimeGenerated desc\r\n// Oql: Type=Event EventID=26328 EventLog="Operations Manager" | Measure count() interval 1DAY // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_ServerRestartTime 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|ServerRestartTime'
  properties: {
    displayName: 'When did my servers initiate restart?'
    category: 'Log Management'
    query: 'search in (Event) "shutdown" and EventLog == "System" and Source == "User32" and EventID == 1074 | sort by TimeGenerated desc | project TimeGenerated, Computer\r\n// Oql: shutdown Type=Event EventLog=System Source=User32 EventID=1074 | Select TimeGenerated,Computer // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_Show404PagesList 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|Show404PagesList'
  properties: {
    displayName: 'Shows which pages people are getting a 404 for'
    category: 'Log Management'
    query: 'search scStatus == 404 | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by csUriStem\r\n// Oql: Type=W3CIISLog scStatus=404 | Measure count() by csUriStem // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_ShowServersThrowingInternalServerError 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|ShowServersThrowingInternalServerError'
  properties: {
    displayName: 'Shows servers that are throwing internal server error'
    category: 'Log Management'
    query: 'search scStatus == 500 | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = count() by sComputerName\r\n// Oql: Type=W3CIISLog scStatus=500 | Measure count() by sComputerName // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_TotalBytesReceivedByEachAzureRoleInstance 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|TotalBytesReceivedByEachAzureRoleInstance'
  properties: {
    displayName: 'Total Bytes received by each Azure Role Instance'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(csBytes) by RoleInstance\r\n// Oql: Type=W3CIISLog | Measure Sum(csBytes) by RoleInstance // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_TotalBytesReceivedByEachIISComputer 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|TotalBytesReceivedByEachIISComputer'
  properties: {
    displayName: 'Total Bytes received by each IIS Computer'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(csBytes) by Computer | limit 500000\r\n// Oql: Type=W3CIISLog | Measure Sum(csBytes) by Computer | top 500000 // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_TotalBytesRespondedToClientsByClientIPAddress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|TotalBytesRespondedToClientsByClientIPAddress'
  properties: {
    displayName: 'Total Bytes responded back to clients by Client IP Address'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(scBytes) by cIP\r\n// Oql: Type=W3CIISLog | Measure Sum(scBytes) by cIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_TotalBytesRespondedToClientsByEachIISServerIPAddress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|TotalBytesRespondedToClientsByEachIISServerIPAddress'
  properties: {
    displayName: 'Total Bytes responded back to clients by each IIS ServerIP Address'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(scBytes) by sIP\r\n// Oql: Type=W3CIISLog | Measure Sum(scBytes) by sIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_TotalBytesSentByClientIPAddress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|TotalBytesSentByClientIPAddress'
  properties: {
    displayName: 'Total Bytes sent by Client IP Address'
    category: 'Log Management'
    query: 'search * | extend Type = $table | where Type == W3CIISLog | summarize AggregatedValue = sum(csBytes) by cIP\r\n// Oql: Type=W3CIISLog | Measure Sum(csBytes) by cIP // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PEF: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_WarningEvents 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|WarningEvents'
  properties: {
    displayName: 'All Events with level "Warning"'
    category: 'Log Management'
    query: 'Event | where EventLevelName == "warning" | sort by TimeGenerated desc\r\n// Oql: Type=Event EventLevelName=warning // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_WindowsFireawallPolicySettingsChanged 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|WindowsFireawallPolicySettingsChanged'
  properties: {
    displayName: 'Windows Firewall Policy settings have changed'
    category: 'Log Management'
    query: 'Event | where EventLog == "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" and EventID == 2008 | sort by TimeGenerated desc\r\n// Oql: Type=Event EventLog="Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" EventID=2008 // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_LogManagement_workspaces_SEC598_Workspace_name_LogManagement_WindowsFireawallPolicySettingsChangedByMachines 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogManagement(${workspaces_SEC598_Workspace_name})_LogManagement|WindowsFireawallPolicySettingsChangedByMachines'
  properties: {
    displayName: 'On which machines and how many times have Windows Firewall Policy settings changed'
    category: 'Log Management'
    query: 'Event | where EventLog == "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" and EventID == 2008 | summarize AggregatedValue = count() by Computer | limit 500000\r\n// Oql: Type=Event EventLog="Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" EventID=2008 | measure count() by Computer | top 500000 // Args: {OQ: True; WorkspaceId: 00000000-0000-0000-0000-000000000000} // Settings: {PTT: True; SortI: True; SortF: True} // Version: 0.1.122'
    version: 2
  }
}

resource workspaces_SEC598_Workspace_name_AACAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AACAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AACAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AACHttpRequest 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AACHttpRequest'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AACHttpRequest'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADB2CRequestLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADB2CRequestLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADB2CRequestLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADCustomSecurityAttributeAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADCustomSecurityAttributeAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADCustomSecurityAttributeAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesAccountLogon 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesAccountLogon'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesAccountLogon'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesAccountManagement 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesAccountManagement'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesAccountManagement'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesDirectoryServiceAccess 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesDirectoryServiceAccess'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesDirectoryServiceAccess'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesDNSAuditsDynamicUpdates 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesDNSAuditsDynamicUpdates'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesDNSAuditsDynamicUpdates'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesDNSAuditsGeneral 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesDNSAuditsGeneral'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesDNSAuditsGeneral'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesLogonLogoff 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesLogonLogoff'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesLogonLogoff'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesPolicyChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesPolicyChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesPolicyChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesPrivilegeUse 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesPrivilegeUse'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesPrivilegeUse'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADDomainServicesSystemSecurity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADDomainServicesSystemSecurity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADDomainServicesSystemSecurity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADManagedIdentitySignInLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADManagedIdentitySignInLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADManagedIdentitySignInLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADNonInteractiveUserSignInLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADNonInteractiveUserSignInLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADNonInteractiveUserSignInLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADProvisioningLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADProvisioningLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADProvisioningLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADRiskyServicePrincipals 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADRiskyServicePrincipals'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADRiskyServicePrincipals'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADRiskyUsers 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADRiskyUsers'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADRiskyUsers'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADServicePrincipalRiskEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADServicePrincipalRiskEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADServicePrincipalRiskEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADServicePrincipalSignInLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADServicePrincipalSignInLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADServicePrincipalSignInLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AADUserRiskEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AADUserRiskEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AADUserRiskEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ABSBotRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ABSBotRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ABSBotRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ABSChannelToBotRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ABSChannelToBotRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ABSChannelToBotRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ABSDependenciesRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ABSDependenciesRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ABSDependenciesRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACICollaborationAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACICollaborationAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACICollaborationAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACRConnectedClientList 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACRConnectedClientList'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACRConnectedClientList'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSAuthIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSAuthIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSAuthIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSBillingUsage 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSBillingUsage'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSBillingUsage'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallAutomationIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallAutomationIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallAutomationIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallAutomationMediaSummary 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallAutomationMediaSummary'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallAutomationMediaSummary'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallClientMediaStatsTimeSeries 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallClientMediaStatsTimeSeries'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallClientMediaStatsTimeSeries'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallClientOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallClientOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallClientOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallClosedCaptionsSummary 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallClosedCaptionsSummary'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallClosedCaptionsSummary'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallDiagnostics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallDiagnostics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallDiagnostics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallRecordingIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallRecordingIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallRecordingIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallRecordingSummary 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallRecordingSummary'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallRecordingSummary'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallSummary 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallSummary'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallSummary'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSCallSurvey 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSCallSurvey'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSCallSurvey'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSChatIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSChatIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSChatIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSEmailSendMailOperational 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSEmailSendMailOperational'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSEmailSendMailOperational'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSEmailStatusUpdateOperational 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSEmailStatusUpdateOperational'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSEmailStatusUpdateOperational'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSEmailUserEngagementOperational 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSEmailUserEngagementOperational'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSEmailUserEngagementOperational'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSJobRouterIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSJobRouterIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSJobRouterIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSNetworkTraversalDiagnostics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSNetworkTraversalDiagnostics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSNetworkTraversalDiagnostics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSNetworkTraversalIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSNetworkTraversalIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSNetworkTraversalIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSRoomsIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSRoomsIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSRoomsIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ACSSMSIncomingOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ACSSMSIncomingOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ACSSMSIncomingOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AddonAzureBackupAlerts 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AddonAzureBackupAlerts'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AddonAzureBackupAlerts'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AddonAzureBackupJobs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AddonAzureBackupJobs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AddonAzureBackupJobs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AddonAzureBackupPolicy 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AddonAzureBackupPolicy'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AddonAzureBackupPolicy'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AddonAzureBackupProtectedInstance 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AddonAzureBackupProtectedInstance'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AddonAzureBackupProtectedInstance'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AddonAzureBackupStorage 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AddonAzureBackupStorage'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AddonAzureBackupStorage'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFActivityRun 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFActivityRun'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFActivityRun'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFAirflowSchedulerLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFAirflowSchedulerLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFAirflowSchedulerLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFAirflowTaskLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFAirflowTaskLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFAirflowTaskLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFAirflowWebLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFAirflowWebLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFAirflowWebLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFAirflowWorkerLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFAirflowWorkerLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFAirflowWorkerLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFPipelineRun 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFPipelineRun'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFPipelineRun'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSandboxActivityRun 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSandboxActivityRun'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSandboxActivityRun'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSandboxPipelineRun 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSandboxPipelineRun'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSandboxPipelineRun'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSignInLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSignInLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSignInLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISIntegrationRuntimeLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISIntegrationRuntimeLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISIntegrationRuntimeLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISPackageEventMessageContext 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISPackageEventMessageContext'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISPackageEventMessageContext'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISPackageEventMessages 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISPackageEventMessages'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISPackageEventMessages'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISPackageExecutableStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISPackageExecutableStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISPackageExecutableStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISPackageExecutionComponentPhases 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISPackageExecutionComponentPhases'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISPackageExecutionComponentPhases'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFSSISPackageExecutionDataStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFSSISPackageExecutionDataStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFSSISPackageExecutionDataStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADFTriggerRun 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADFTriggerRun'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADFTriggerRun'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADPAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADPAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADPAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADPDiagnostics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADPDiagnostics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADPDiagnostics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADPRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADPRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADPRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADReplicationResult 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADReplicationResult'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADReplicationResult'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADSecurityAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADSecurityAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADSecurityAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADTDataHistoryOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADTDataHistoryOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADTDataHistoryOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADTDigitalTwinsOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADTDigitalTwinsOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADTDigitalTwinsOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADTEventRoutesOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADTEventRoutesOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADTEventRoutesOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADTModelsOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADTModelsOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADTModelsOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADTQueryOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADTQueryOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADTQueryOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXCommand 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXCommand'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXCommand'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXIngestionBatching 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXIngestionBatching'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXIngestionBatching'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXJournal 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXJournal'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXJournal'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXQuery 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXQuery'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXQuery'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXTableDetails 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXTableDetails'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXTableDetails'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ADXTableUsageStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ADXTableUsageStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ADXTableUsageStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AegDataPlaneRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AegDataPlaneRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AegDataPlaneRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AegDeliveryFailureLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AegDeliveryFailureLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AegDeliveryFailureLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AegPublishFailureLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AegPublishFailureLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AegPublishFailureLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AEWAssignmentBlobLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AEWAssignmentBlobLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AEWAssignmentBlobLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AEWAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AEWAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AEWAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AEWComputePipelinesLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AEWComputePipelinesLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AEWComputePipelinesLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AFSAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AFSAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AFSAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AGCAccessLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AGCAccessLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AGCAccessLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodApplicationAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodApplicationAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodApplicationAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodFarmManagementLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodFarmManagementLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodFarmManagementLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodFarmOperationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodFarmOperationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodFarmOperationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodInsightLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodInsightLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodInsightLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodJobProcessedLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodJobProcessedLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodJobProcessedLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodModelInferenceLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodModelInferenceLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodModelInferenceLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodProviderAuthLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodProviderAuthLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodProviderAuthLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodSatelliteLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodSatelliteLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodSatelliteLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodSensorManagementLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodSensorManagementLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodSensorManagementLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AgriFoodWeatherLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AgriFoodWeatherLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AgriFoodWeatherLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AGSGrafanaLoginEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AGSGrafanaLoginEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AGSGrafanaLoginEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AGWAccessLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AGWAccessLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AGWAccessLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AGWFirewallLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AGWFirewallLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AGWFirewallLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AGWPerformanceLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AGWPerformanceLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AGWPerformanceLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AHDSDicomAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AHDSDicomAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AHDSDicomAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AHDSDicomDiagnosticLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AHDSDicomDiagnosticLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AHDSDicomDiagnosticLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AHDSMedTechDiagnosticLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AHDSMedTechDiagnosticLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AHDSMedTechDiagnosticLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AirflowDagProcessingLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AirflowDagProcessingLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AirflowDagProcessingLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AKSAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AKSAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AKSAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AKSAuditAdmin 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AKSAuditAdmin'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AKSAuditAdmin'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AKSControlPlane 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AKSControlPlane'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AKSControlPlane'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Alert 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Alert'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Alert'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AlertEvidence 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AlertEvidence'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AlertEvidence'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AlertInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AlertInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AlertInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlComputeClusterEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlComputeClusterEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlComputeClusterEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlComputeClusterNodeEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlComputeClusterNodeEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlComputeClusterNodeEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlComputeCpuGpuUtilization 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlComputeCpuGpuUtilization'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlComputeCpuGpuUtilization'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlComputeInstanceEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlComputeInstanceEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlComputeInstanceEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlComputeJobEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlComputeJobEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlComputeJobEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlDataLabelEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlDataLabelEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlDataLabelEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlDataSetEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlDataSetEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlDataSetEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlDataStoreEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlDataStoreEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlDataStoreEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlDeploymentEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlDeploymentEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlDeploymentEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlEnvironmentEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlEnvironmentEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlEnvironmentEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlInferencingEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlInferencingEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlInferencingEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlModelsEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlModelsEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlModelsEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlOnlineEndpointConsoleLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlOnlineEndpointConsoleLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlOnlineEndpointConsoleLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlOnlineEndpointEventLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlOnlineEndpointEventLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlOnlineEndpointEventLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlOnlineEndpointTrafficLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlOnlineEndpointTrafficLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlOnlineEndpointTrafficLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlPipelineEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlPipelineEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlPipelineEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlRegistryReadEventsLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlRegistryReadEventsLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlRegistryReadEventsLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlRegistryWriteEventsLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlRegistryWriteEventsLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlRegistryWriteEventsLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlRunEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlRunEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlRunEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AmlRunStatusChangedEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AmlRunStatusChangedEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AmlRunStatusChangedEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AMSKeyDeliveryRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AMSKeyDeliveryRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AMSKeyDeliveryRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AMSLiveEventOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AMSLiveEventOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AMSLiveEventOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AMSMediaAccountHealth 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AMSMediaAccountHealth'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AMSMediaAccountHealth'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AMSStreamingEndpointRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AMSStreamingEndpointRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AMSStreamingEndpointRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AMWMetricsUsageDetails 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AMWMetricsUsageDetails'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AMWMetricsUsageDetails'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ANFFileAccess 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ANFFileAccess'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ANFFileAccess'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Anomalies 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Anomalies'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Anomalies'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AOIDatabaseQuery 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AOIDatabaseQuery'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AOIDatabaseQuery'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AOIDigestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AOIDigestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AOIDigestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AOIStorage 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AOIStorage'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AOIStorage'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ApiManagementGatewayLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ApiManagementGatewayLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ApiManagementGatewayLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ApiManagementWebSocketConnectionLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ApiManagementWebSocketConnectionLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ApiManagementWebSocketConnectionLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppAvailabilityResults 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppAvailabilityResults'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppAvailabilityResults'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppBrowserTimings 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppBrowserTimings'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppBrowserTimings'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppCenterError 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppCenterError'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppCenterError'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppDependencies 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppDependencies'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppDependencies'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppEnvSpringAppConsoleLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppEnvSpringAppConsoleLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppEnvSpringAppConsoleLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppEvents'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppEvents'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppExceptions 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppExceptions'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppExceptions'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppMetrics'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppMetrics'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppPageViews 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPageViews'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppPageViews'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppPerformanceCounters 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPerformanceCounters'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppPerformanceCounters'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppPlatformBuildLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPlatformBuildLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppPlatformBuildLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppPlatformContainerEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPlatformContainerEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppPlatformContainerEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppPlatformIngressLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPlatformIngressLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppPlatformIngressLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppPlatformLogsforSpring 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPlatformLogsforSpring'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppPlatformLogsforSpring'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppPlatformSystemLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppPlatformSystemLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppPlatformSystemLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppRequests'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppRequests'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceAntivirusScanAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceAntivirusScanAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceAntivirusScanAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceAppLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceAppLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceAppLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceAuthenticationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceAuthenticationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceAuthenticationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceConsoleLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceConsoleLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceConsoleLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceEnvironmentPlatformLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceEnvironmentPlatformLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceEnvironmentPlatformLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceFileAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceFileAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceFileAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceHTTPLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceHTTPLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceHTTPLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceIPSecAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceIPSecAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceIPSecAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServicePlatformLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServicePlatformLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServicePlatformLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppServiceServerlessSecurityPluginData 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppServiceServerlessSecurityPluginData'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AppServiceServerlessSecurityPluginData'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AppSystemEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppSystemEvents'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppSystemEvents'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AppTraces 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AppTraces'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AppTraces'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_ArcK8sAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ArcK8sAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ArcK8sAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ArcK8sAuditAdmin 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ArcK8sAuditAdmin'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ArcK8sAuditAdmin'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ArcK8sControlPlane 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ArcK8sControlPlane'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ArcK8sControlPlane'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASCAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASCAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASCAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASCDeviceEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASCDeviceEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASCDeviceEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimAuditEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimAuditEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimAuditEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimAuthenticationEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimAuthenticationEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimAuthenticationEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimDhcpEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimDhcpEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimDhcpEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimDnsActivityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimDnsActivityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimDnsActivityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimFileEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimFileEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimFileEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimNetworkSessionLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimNetworkSessionLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimNetworkSessionLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimProcessEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimProcessEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimProcessEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimRegistryEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimRegistryEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimRegistryEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimUserManagementActivityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimUserManagementActivityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimUserManagementActivityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASimWebSessionLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASimWebSessionLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASimWebSessionLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASRJobs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASRJobs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASRJobs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ASRReplicatedItems 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ASRReplicatedItems'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ASRReplicatedItems'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ATCExpressRouteCircuitIpfix 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ATCExpressRouteCircuitIpfix'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ATCExpressRouteCircuitIpfix'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AUIEventsAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AUIEventsAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AUIEventsAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AUIEventsOperational 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AUIEventsOperational'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AUIEventsOperational'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AutoscaleEvaluationsLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AutoscaleEvaluationsLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AutoscaleEvaluationsLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AutoscaleScaleActionsLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AutoscaleScaleActionsLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AutoscaleScaleActionsLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AVNMConnectivityConfigurationChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AVNMConnectivityConfigurationChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AVNMConnectivityConfigurationChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AVNMIPAMPoolAllocationChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AVNMIPAMPoolAllocationChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AVNMIPAMPoolAllocationChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AVNMNetworkGroupMembershipChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AVNMNetworkGroupMembershipChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AVNMNetworkGroupMembershipChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AVNMRuleCollectionChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AVNMRuleCollectionChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AVNMRuleCollectionChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AVSSyslog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AVSSyslog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AVSSyslog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AWSCloudTrail 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AWSCloudTrail'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AWSCloudTrail'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AWSCloudWatch 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AWSCloudWatch'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AWSCloudWatch'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AWSGuardDuty 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AWSGuardDuty'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AWSGuardDuty'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AWSVPCFlow 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AWSVPCFlow'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AWSVPCFlow'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWApplicationRule 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWApplicationRule'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWApplicationRule'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWApplicationRuleAggregation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWApplicationRuleAggregation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWApplicationRuleAggregation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWDnsQuery 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWDnsQuery'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWDnsQuery'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWFatFlow 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWFatFlow'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWFatFlow'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWFlowTrace 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWFlowTrace'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWFlowTrace'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWIdpsSignature 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWIdpsSignature'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWIdpsSignature'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWInternalFqdnResolutionFailure 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWInternalFqdnResolutionFailure'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWInternalFqdnResolutionFailure'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWNatRule 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWNatRule'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWNatRule'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWNatRuleAggregation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWNatRuleAggregation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWNatRuleAggregation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWNetworkRule 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWNetworkRule'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWNetworkRule'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWNetworkRuleAggregation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWNetworkRuleAggregation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWNetworkRuleAggregation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZFWThreatIntel 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZFWThreatIntel'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZFWThreatIntel'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZKVAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZKVAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZKVAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZKVPolicyEvaluationDetailsLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZKVPolicyEvaluationDetailsLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZKVPolicyEvaluationDetailsLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSApplicationMetricLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSApplicationMetricLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSApplicationMetricLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSArchiveLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSArchiveLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSArchiveLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSAutoscaleLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSAutoscaleLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSAutoscaleLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSCustomerManagedKeyUserLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSCustomerManagedKeyUserLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSCustomerManagedKeyUserLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSHybridConnectionsEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSHybridConnectionsEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSHybridConnectionsEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSKafkaCoordinatorLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSKafkaCoordinatorLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSKafkaCoordinatorLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSKafkaUserErrorLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSKafkaUserErrorLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSKafkaUserErrorLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSOperationalLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSOperationalLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSOperationalLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSRunTimeAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSRunTimeAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSRunTimeAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AZMSVnetConnectionEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AZMSVnetConnectionEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AZMSVnetConnectionEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureActivity'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'AzureActivity'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_AzureActivityV2 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureActivityV2'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureActivityV2'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureAttestationDiagnostics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureAttestationDiagnostics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureAttestationDiagnostics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureBackupOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureBackupOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureBackupOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureCloudHsmAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureCloudHsmAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureCloudHsmAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureDevOpsAuditing 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureDevOpsAuditing'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureDevOpsAuditing'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureLoadTestingOperation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureLoadTestingOperation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureLoadTestingOperation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_AzureMetricsV2 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'AzureMetricsV2'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'AzureMetricsV2'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_BaiClusterEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'BaiClusterEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'BaiClusterEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_BaiClusterNodeEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'BaiClusterNodeEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'BaiClusterNodeEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_BaiJobEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'BaiJobEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'BaiJobEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_BlockchainApplicationLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'BlockchainApplicationLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'BlockchainApplicationLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_BlockchainProxyLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'BlockchainProxyLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'BlockchainProxyLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CassandraAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CassandraAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CassandraAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CassandraLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CassandraLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CassandraLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CCFApplicationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CCFApplicationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CCFApplicationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBCassandraRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBCassandraRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBCassandraRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBControlPlaneRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBControlPlaneRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBControlPlaneRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBDataPlaneRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBDataPlaneRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBDataPlaneRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBGremlinRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBGremlinRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBGremlinRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBMongoRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBMongoRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBMongoRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBPartitionKeyRUConsumption 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBPartitionKeyRUConsumption'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBPartitionKeyRUConsumption'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBPartitionKeyStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBPartitionKeyStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBPartitionKeyStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CDBQueryRuntimeStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CDBQueryRuntimeStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CDBQueryRuntimeStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ChaosStudioExperimentEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ChaosStudioExperimentEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ChaosStudioExperimentEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CHSMManagementAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CHSMManagementAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CHSMManagementAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CIEventsAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CIEventsAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CIEventsAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CIEventsOperational 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CIEventsOperational'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CIEventsOperational'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CloudAppEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CloudAppEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CloudAppEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CommonSecurityLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CommonSecurityLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CommonSecurityLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ComputerGroup 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ComputerGroup'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ComputerGroup'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ConfidentialWatchlist 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ConfidentialWatchlist'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ConfidentialWatchlist'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerAppConsoleLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerAppConsoleLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerAppConsoleLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerAppSystemLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerAppSystemLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerAppSystemLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerImageInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerImageInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerImageInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerInstanceLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerInstanceLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerInstanceLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerLogV2 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerLogV2'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerLogV2'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerNodeInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerNodeInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerNodeInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerRegistryLoginEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerRegistryLoginEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerRegistryLoginEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerRegistryRepositoryEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerRegistryRepositoryEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerRegistryRepositoryEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ContainerServiceLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ContainerServiceLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ContainerServiceLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_CoreAzureBackup 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'CoreAzureBackup'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'CoreAzureBackup'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksAccounts 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksAccounts'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksAccounts'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksBrickStoreHttpGateway 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksBrickStoreHttpGateway'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksBrickStoreHttpGateway'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksCapsule8Dataplane 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksCapsule8Dataplane'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksCapsule8Dataplane'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksClamAVScan 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksClamAVScan'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksClamAVScan'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksCloudStorageMetadata 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksCloudStorageMetadata'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksCloudStorageMetadata'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksClusterLibraries 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksClusterLibraries'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksClusterLibraries'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksClusters 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksClusters'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksClusters'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksDashboards 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksDashboards'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksDashboards'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksDatabricksSQL 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksDatabricksSQL'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksDatabricksSQL'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksDataMonitoring 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksDataMonitoring'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksDataMonitoring'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksDBFS 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksDBFS'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksDBFS'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksDeltaPipelines 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksDeltaPipelines'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksDeltaPipelines'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksFeatureStore 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksFeatureStore'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksFeatureStore'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksFilesystem 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksFilesystem'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksFilesystem'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksGenie 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksGenie'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksGenie'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksGitCredentials 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksGitCredentials'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksGitCredentials'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksGlobalInitScripts 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksGlobalInitScripts'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksGlobalInitScripts'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksIAMRole 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksIAMRole'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksIAMRole'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksIngestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksIngestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksIngestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksInstancePools 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksInstancePools'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksInstancePools'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksJobs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksJobs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksJobs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksLineageTracking 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksLineageTracking'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksLineageTracking'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksMarketplaceConsumer 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksMarketplaceConsumer'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksMarketplaceConsumer'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksMLflowAcledArtifact 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksMLflowAcledArtifact'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksMLflowAcledArtifact'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksMLflowExperiment 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksMLflowExperiment'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksMLflowExperiment'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksModelRegistry 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksModelRegistry'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksModelRegistry'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksNotebook 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksNotebook'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksNotebook'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksPartnerHub 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksPartnerHub'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksPartnerHub'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksPredictiveOptimization 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksPredictiveOptimization'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksPredictiveOptimization'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksRemoteHistoryService 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksRemoteHistoryService'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksRemoteHistoryService'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksRepos 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksRepos'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksRepos'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksSecrets 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksSecrets'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksSecrets'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksServerlessRealTimeInference 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksServerlessRealTimeInference'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksServerlessRealTimeInference'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksSQL 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksSQL'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksSQL'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksSQLPermissions 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksSQLPermissions'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksSQLPermissions'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksSSH 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksSSH'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksSSH'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksTables 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksTables'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksTables'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksUnityCatalog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksUnityCatalog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksUnityCatalog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksWebTerminal 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksWebTerminal'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksWebTerminal'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DatabricksWorkspace 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DatabricksWorkspace'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DatabricksWorkspace'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DataTransferOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DataTransferOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DataTransferOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DataverseActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DataverseActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DataverseActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DCRLogErrors 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DCRLogErrors'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DCRLogErrors'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DCRLogTroubleshooting 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DCRLogTroubleshooting'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DCRLogTroubleshooting'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DevCenterBillingEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DevCenterBillingEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DevCenterBillingEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DevCenterDiagnosticLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DevCenterDiagnosticLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DevCenterDiagnosticLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DevCenterResourceOperationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DevCenterResourceOperationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DevCenterResourceOperationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceFileCertificateInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceFileCertificateInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceFileCertificateInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceFileEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceFileEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceFileEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceImageLoadEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceImageLoadEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceImageLoadEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceLogonEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceLogonEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceLogonEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceNetworkEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceNetworkEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceNetworkEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceNetworkInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceNetworkInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceNetworkInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceProcessEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceProcessEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceProcessEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceRegistryEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceRegistryEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceRegistryEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceTvmSecureConfigurationAssessment 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceTvmSecureConfigurationAssessment'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceTvmSecureConfigurationAssessment'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceTvmSecureConfigurationAssessmentKB 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceTvmSecureConfigurationAssessmentKB'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceTvmSecureConfigurationAssessmentKB'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceTvmSoftwareInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceTvmSoftwareInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceTvmSoftwareInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceTvmSoftwareVulnerabilities 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceTvmSoftwareVulnerabilities'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceTvmSoftwareVulnerabilities'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DeviceTvmSoftwareVulnerabilitiesKB 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DeviceTvmSoftwareVulnerabilitiesKB'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DeviceTvmSoftwareVulnerabilitiesKB'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DnsEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DnsEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DnsEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DnsInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DnsInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DnsInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DNSQueryLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DNSQueryLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DNSQueryLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DSMAzureBlobStorageLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DSMAzureBlobStorageLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DSMAzureBlobStorageLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DSMDataClassificationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DSMDataClassificationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DSMDataClassificationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DSMDataLabelingLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DSMDataLabelingLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DSMDataLabelingLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Dynamics365Activity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Dynamics365Activity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Dynamics365Activity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_DynamicSummary 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'DynamicSummary'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'DynamicSummary'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EGNFailedMqttConnections 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EGNFailedMqttConnections'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EGNFailedMqttConnections'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EGNFailedMqttPublishedMessages 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EGNFailedMqttPublishedMessages'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EGNFailedMqttPublishedMessages'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EGNFailedMqttSubscriptions 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EGNFailedMqttSubscriptions'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EGNFailedMqttSubscriptions'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EGNMqttDisconnections 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EGNMqttDisconnections'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EGNMqttDisconnections'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EGNSuccessfulMqttConnections 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EGNSuccessfulMqttConnections'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EGNSuccessfulMqttConnections'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EmailAttachmentInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EmailAttachmentInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EmailAttachmentInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EmailEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EmailEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EmailEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EmailPostDeliveryEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EmailPostDeliveryEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EmailPostDeliveryEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EmailUrlInfo 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EmailUrlInfo'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EmailUrlInfo'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_EnrichedMicrosoft365AuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'EnrichedMicrosoft365AuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'EnrichedMicrosoft365AuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ETWEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ETWEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ETWEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Event 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Event'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Event'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ExchangeAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ExchangeAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ExchangeAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ExchangeOnlineAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ExchangeOnlineAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ExchangeOnlineAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_FailedIngestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'FailedIngestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'FailedIngestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_FunctionAppLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'FunctionAppLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'FunctionAppLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_GCPAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'GCPAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'GCPAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_GoogleCloudSCC 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'GoogleCloudSCC'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'GoogleCloudSCC'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightAmbariClusterAlerts 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightAmbariClusterAlerts'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightAmbariClusterAlerts'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightAmbariSystemMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightAmbariSystemMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightAmbariSystemMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightGatewayAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightGatewayAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightGatewayAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHadoopAndYarnLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHadoopAndYarnLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHadoopAndYarnLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHadoopAndYarnMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHadoopAndYarnMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHadoopAndYarnMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHBaseLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHBaseLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHBaseLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHBaseMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHBaseMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHBaseMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHiveAndLLAPLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHiveAndLLAPLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHiveAndLLAPLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHiveAndLLAPMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHiveAndLLAPMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHiveAndLLAPMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHiveQueryAppStats 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHiveQueryAppStats'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHiveQueryAppStats'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightHiveTezAppStats 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightHiveTezAppStats'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightHiveTezAppStats'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightJupyterNotebookEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightJupyterNotebookEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightJupyterNotebookEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightKafkaLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightKafkaLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightKafkaLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightKafkaMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightKafkaMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightKafkaMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightKafkaServerLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightKafkaServerLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightKafkaServerLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightOozieLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightOozieLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightOozieLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightRangerAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightRangerAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightRangerAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSecurityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSecurityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSecurityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkApplicationEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkApplicationEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkApplicationEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkBlockManagerEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkBlockManagerEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkBlockManagerEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkEnvironmentEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkEnvironmentEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkEnvironmentEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkExecutorEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkExecutorEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkExecutorEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkExtraEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkExtraEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkExtraEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkJobEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkJobEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkJobEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkSQLExecutionEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkSQLExecutionEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkSQLExecutionEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkStageEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkStageEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkStageEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkStageTaskAccumulables 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkStageTaskAccumulables'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkStageTaskAccumulables'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightSparkTaskEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightSparkTaskEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightSparkTaskEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightStormLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightStormLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightStormLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightStormMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightStormMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightStormMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HDInsightStormTopologyMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HDInsightStormTopologyMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HDInsightStormTopologyMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HealthStateChangeEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HealthStateChangeEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HealthStateChangeEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Heartbeat 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Heartbeat'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Heartbeat'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HuntingBookmark 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HuntingBookmark'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HuntingBookmark'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_HuntingBookmarks 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'HuntingBookmarks'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'HuntingBookmarks'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IdentityDirectoryEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IdentityDirectoryEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IdentityDirectoryEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IdentityLogonEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IdentityLogonEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IdentityLogonEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IdentityQueryEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IdentityQueryEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IdentityQueryEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_InsightsMetrics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'InsightsMetrics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'InsightsMetrics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IntuneAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IntuneAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IntuneAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IntuneDeviceComplianceOrg 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IntuneDeviceComplianceOrg'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IntuneDeviceComplianceOrg'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IntuneDevices 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IntuneDevices'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IntuneDevices'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_IntuneOperationalLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'IntuneOperationalLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'IntuneOperationalLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubeEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubeEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubeEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubeHealth 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubeHealth'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubeHealth'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubeMonAgentEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubeMonAgentEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubeMonAgentEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubeNodeInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubeNodeInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubeNodeInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubePodInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubePodInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubePodInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubePVInventory 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubePVInventory'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubePVInventory'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_KubeServices 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'KubeServices'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'KubeServices'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_LAQueryLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LAQueryLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'LAQueryLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_LASummaryLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LASummaryLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'LASummaryLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_LinuxAuditLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LinuxAuditLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'LinuxAuditLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_LogicAppWorkflowRuntime 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'LogicAppWorkflowRuntime'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'LogicAppWorkflowRuntime'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_McasShadowItReporting 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'McasShadowItReporting'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'McasShadowItReporting'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MCCEventLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MCCEventLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MCCEventLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MCVPAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MCVPAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MCVPAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MCVPOperationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MCVPOperationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MCVPOperationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MDECustomCollectionDeviceFileEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MDECustomCollectionDeviceFileEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MDECustomCollectionDeviceFileEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftAzureBastionAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftAzureBastionAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftAzureBastionAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftDataShareReceivedSnapshotLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftDataShareReceivedSnapshotLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftDataShareReceivedSnapshotLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftDataShareSentSnapshotLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftDataShareSentSnapshotLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftDataShareSentSnapshotLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftDataShareShareLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftDataShareShareLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftDataShareShareLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftDynamicsTelemetryPerformanceLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftDynamicsTelemetryPerformanceLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftDynamicsTelemetryPerformanceLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftDynamicsTelemetrySystemMetricsLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftDynamicsTelemetrySystemMetricsLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftDynamicsTelemetrySystemMetricsLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftGraphActivityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftGraphActivityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftGraphActivityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftHealthcareApisAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftHealthcareApisAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftHealthcareApisAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MicrosoftPurviewInformationProtection 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MicrosoftPurviewInformationProtection'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MicrosoftPurviewInformationProtection'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MNFDeviceUpdates 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MNFDeviceUpdates'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MNFDeviceUpdates'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_MNFSystemStateMessageUpdates 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'MNFSystemStateMessageUpdates'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'MNFSystemStateMessageUpdates'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCBMBreakGlassAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCBMBreakGlassAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCBMBreakGlassAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCBMSecurityDefenderLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCBMSecurityDefenderLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCBMSecurityDefenderLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCBMSecurityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCBMSecurityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCBMSecurityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCBMSystemLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCBMSystemLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCBMSystemLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCCKubernetesLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCCKubernetesLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCCKubernetesLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCCVMOrchestrationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCCVMOrchestrationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCCVMOrchestrationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCSStorageAlerts 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCSStorageAlerts'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCSStorageAlerts'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NCSStorageLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NCSStorageLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NCSStorageLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NetworkAccessTraffic 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NetworkAccessTraffic'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NetworkAccessTraffic'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NetworkSessions 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NetworkSessions'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NetworkSessions'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NGXOperationLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NGXOperationLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NGXOperationLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NSPAccessLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NSPAccessLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NSPAccessLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NTAIpDetails 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NTAIpDetails'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NTAIpDetails'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NTANetAnalytics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NTANetAnalytics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NTANetAnalytics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NTATopologyDetails 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NTATopologyDetails'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NTATopologyDetails'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NWConnectionMonitorDestinationListenerResult 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NWConnectionMonitorDestinationListenerResult'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NWConnectionMonitorDestinationListenerResult'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NWConnectionMonitorDNSResult 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NWConnectionMonitorDNSResult'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NWConnectionMonitorDNSResult'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NWConnectionMonitorPathResult 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NWConnectionMonitorPathResult'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NWConnectionMonitorPathResult'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_NWConnectionMonitorTestResult 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'NWConnectionMonitorTestResult'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'NWConnectionMonitorTestResult'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OEPAirFlowTask 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OEPAirFlowTask'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OEPAirFlowTask'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OEPAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OEPAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OEPAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OEPDataplaneLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OEPDataplaneLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OEPDataplaneLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OEPElasticOperator 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OEPElasticOperator'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OEPElasticOperator'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OEPElasticsearch 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OEPElasticsearch'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OEPElasticsearch'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OfficeActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OfficeActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OfficeActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OLPSupplyChainEntityOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OLPSupplyChainEntityOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OLPSupplyChainEntityOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OLPSupplyChainEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OLPSupplyChainEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OLPSupplyChainEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_OmsCustomerProfileFact 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'OmsCustomerProfileFact'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'OmsCustomerProfileFact'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Operation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Operation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Operation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Perf 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Perf'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Perf'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PFTitleAuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PFTitleAuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PFTitleAuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerAppsActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerAppsActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerAppsActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerAutomateActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerAutomateActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerAutomateActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIAuditTenant 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIAuditTenant'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIAuditTenant'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIDatasetsTenant 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIDatasetsTenant'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIDatasetsTenant'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIDatasetsTenantPreview 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIDatasetsTenantPreview'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIDatasetsTenantPreview'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIDatasetsWorkspace 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIDatasetsWorkspace'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIDatasetsWorkspace'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIDatasetsWorkspacePreview 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIDatasetsWorkspacePreview'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIDatasetsWorkspacePreview'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIReportUsageTenant 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIReportUsageTenant'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIReportUsageTenant'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerBIReportUsageWorkspace 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerBIReportUsageWorkspace'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerBIReportUsageWorkspace'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerPlatformAdminActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerPlatformAdminActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerPlatformAdminActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerPlatformConnectorActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerPlatformConnectorActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerPlatformConnectorActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PowerPlatformDlpActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PowerPlatformDlpActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PowerPlatformDlpActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ProjectActivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ProjectActivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ProjectActivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PurviewDataSensitivityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PurviewDataSensitivityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PurviewDataSensitivityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PurviewScanStatusLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PurviewScanStatusLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PurviewScanStatusLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_PurviewSecurityLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'PurviewSecurityLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'PurviewSecurityLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_REDConnectionEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'REDConnectionEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'REDConnectionEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_RemoteNetworkHealthLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'RemoteNetworkHealthLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'RemoteNetworkHealthLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ReservedCommonFields 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ReservedCommonFields'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ReservedCommonFields'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ResourceManagementPublicAccessLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ResourceManagementPublicAccessLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ResourceManagementPublicAccessLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SCCMAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SCCMAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SCCMAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SCOMAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SCOMAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SCOMAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SecurityAlert 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SecurityAlert'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SecurityAlert'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SecurityEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SecurityEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SecurityEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SecurityIncident 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SecurityIncident'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SecurityIncident'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SentinelAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SentinelAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SentinelAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SentinelHealth 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SentinelHealth'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SentinelHealth'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ServiceFabricOperationalEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ServiceFabricOperationalEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ServiceFabricOperationalEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ServiceFabricReliableActorEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ServiceFabricReliableActorEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ServiceFabricReliableActorEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ServiceFabricReliableServiceEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ServiceFabricReliableServiceEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ServiceFabricReliableServiceEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SfBAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SfBAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SfBAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SfBOnlineAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SfBOnlineAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SfBOnlineAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SharePointOnlineAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SharePointOnlineAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SharePointOnlineAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SignalRServiceDiagnosticLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SignalRServiceDiagnosticLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SignalRServiceDiagnosticLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SigninLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SigninLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SigninLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SPAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SPAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SPAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SQLAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SQLAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SQLAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SQLSecurityAuditEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SQLSecurityAuditEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SQLSecurityAuditEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageAntimalwareScanResults 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageAntimalwareScanResults'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageAntimalwareScanResults'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageBlobLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageBlobLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageBlobLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageCacheOperationEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageCacheOperationEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageCacheOperationEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageCacheUpgradeEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageCacheUpgradeEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageCacheUpgradeEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageCacheWarningEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageCacheWarningEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageCacheWarningEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageFileLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageFileLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageFileLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageMalwareScanningResults 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageMalwareScanningResults'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageMalwareScanningResults'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageMoverCopyLogsFailed 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageMoverCopyLogsFailed'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageMoverCopyLogsFailed'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageMoverCopyLogsTransferred 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageMoverCopyLogsTransferred'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageMoverCopyLogsTransferred'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageMoverJobRunLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageMoverJobRunLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageMoverJobRunLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageQueueLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageQueueLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageQueueLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_StorageTableLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'StorageTableLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'StorageTableLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SucceededIngestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SucceededIngestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SucceededIngestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseBigDataPoolApplicationsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseBigDataPoolApplicationsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseBigDataPoolApplicationsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseBuiltinSqlPoolRequestsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseBuiltinSqlPoolRequestsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseBuiltinSqlPoolRequestsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXCommand 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXCommand'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXCommand'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXFailedIngestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXFailedIngestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXFailedIngestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXIngestionBatching 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXIngestionBatching'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXIngestionBatching'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXQuery 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXQuery'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXQuery'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXSucceededIngestion 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXSucceededIngestion'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXSucceededIngestion'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXTableDetails 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXTableDetails'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXTableDetails'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseDXTableUsageStatistics 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseDXTableUsageStatistics'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseDXTableUsageStatistics'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseGatewayApiRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseGatewayApiRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseGatewayApiRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseGatewayEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseGatewayEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseGatewayEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationActivityRuns 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationActivityRuns'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationActivityRuns'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationActivityRunsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationActivityRunsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationActivityRunsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationPipelineRuns 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationPipelineRuns'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationPipelineRuns'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationPipelineRunsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationPipelineRunsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationPipelineRunsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationTriggerRuns 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationTriggerRuns'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationTriggerRuns'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseIntegrationTriggerRunsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseIntegrationTriggerRunsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseIntegrationTriggerRunsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseLinkEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseLinkEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseLinkEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseRBACEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseRBACEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseRBACEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseRbacOperations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseRbacOperations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseRbacOperations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseScopePoolScopeJobsEnded 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseScopePoolScopeJobsEnded'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseScopePoolScopeJobsEnded'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseScopePoolScopeJobsStateChange 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseScopePoolScopeJobsStateChange'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseScopePoolScopeJobsStateChange'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseSqlPoolDmsWorkers 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseSqlPoolDmsWorkers'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseSqlPoolDmsWorkers'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseSqlPoolExecRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseSqlPoolExecRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseSqlPoolExecRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseSqlPoolRequestSteps 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseSqlPoolRequestSteps'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseSqlPoolRequestSteps'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseSqlPoolSqlRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseSqlPoolSqlRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseSqlPoolSqlRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_SynapseSqlPoolWaits 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'SynapseSqlPoolWaits'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SynapseSqlPoolWaits'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Syslog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Syslog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Syslog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_ThreatIntelligenceIndicator 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'ThreatIntelligenceIndicator'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'ThreatIntelligenceIndicator'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_TSIIngress 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'TSIIngress'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'TSIIngress'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCClient 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCClient'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCClient'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCClientReadinessStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCClientReadinessStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCClientReadinessStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCClientUpdateStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCClientUpdateStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCClientUpdateStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCDeviceAlert 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCDeviceAlert'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCDeviceAlert'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCDOAggregatedStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCDOAggregatedStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCDOAggregatedStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCDOStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCDOStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCDOStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCServiceUpdateStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCServiceUpdateStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCServiceUpdateStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UCUpdateAlert 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UCUpdateAlert'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UCUpdateAlert'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_UrlClickEvents 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'UrlClickEvents'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'UrlClickEvents'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Usage 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Usage'
  properties: {
    totalRetentionInDays: 90
    plan: 'Analytics'
    schema: {
      name: 'Usage'
    }
    retentionInDays: 90
  }
}

resource workspaces_SEC598_Workspace_name_VCoreMongoRequests 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VCoreMongoRequests'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VCoreMongoRequests'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VIAudit 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VIAudit'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VIAudit'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VIIndexing 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VIIndexing'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VIIndexing'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VMBoundPort 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VMBoundPort'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VMBoundPort'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VMComputer 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VMComputer'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VMComputer'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VMConnection 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VMConnection'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VMConnection'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_VMProcess 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'VMProcess'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'VMProcess'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_W3CIISLog 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'W3CIISLog'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'W3CIISLog'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Watchlist 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Watchlist'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Watchlist'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WebPubSubConnectivity 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WebPubSubConnectivity'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WebPubSubConnectivity'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WebPubSubHttpRequest 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WebPubSubHttpRequest'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WebPubSubHttpRequest'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WebPubSubMessaging 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WebPubSubMessaging'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WebPubSubMessaging'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_Windows365AuditLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'Windows365AuditLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'Windows365AuditLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WindowsClientAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WindowsClientAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WindowsClientAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WindowsEvent 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WindowsEvent'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WindowsEvent'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WindowsServerAssessmentRecommendation 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WindowsServerAssessmentRecommendation'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WindowsServerAssessmentRecommendation'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WorkloadDiagnosticLogs 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WorkloadDiagnosticLogs'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WorkloadDiagnosticLogs'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDAgentHealthStatus 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDAgentHealthStatus'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDAgentHealthStatus'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDAutoscaleEvaluationPooled 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDAutoscaleEvaluationPooled'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDAutoscaleEvaluationPooled'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDCheckpoints 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDCheckpoints'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDCheckpoints'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDConnectionGraphicsDataPreview 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDConnectionGraphicsDataPreview'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDConnectionGraphicsDataPreview'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDConnectionNetworkData 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDConnectionNetworkData'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDConnectionNetworkData'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDConnections 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDConnections'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDConnections'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDErrors 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDErrors'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDErrors'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDFeeds 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDFeeds'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDFeeds'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDHostRegistrations 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDHostRegistrations'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDHostRegistrations'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDManagement 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDManagement'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDManagement'
    }
    retentionInDays: 30
  }
}

resource workspaces_SEC598_Workspace_name_WVDSessionHostManagement 'Microsoft.OperationalInsights/workspaces/tables@2021-12-01-preview' = {
  parent: workspaces_SEC598_Workspace_name_resource
  name: 'WVDSessionHostManagement'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'WVDSessionHostManagement'
    }
    retentionInDays: 30
  }
}

resource solutions_SecurityInsights_sec598_workspace_name_resource 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: solutions_SecurityInsights_sec598_workspace_name
  location: location
  plan: {
    name: 'SecurityInsights(sec598-workspace)'
    promotionCode: ''
    product: 'OMSGallery/SecurityInsights'
    publisher: 'Microsoft'
  }
  properties: {
    workspaceResourceId: workspaces_SEC598_Workspace_name_resource.id
    containedResources: []
  }
}

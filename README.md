# Instructions

This is the README file for using sample orchestration cookbook 
automatically to deploy CentrifyDC or CentrifyCC in AWS OpsWorks.

Currently, we only support Stack for chef 12. </br>
We support the following platforms currently:</br>
Amazon Linux</br>
Centos 7</br>
Red Hat Enterprise 7</br>
Ubuntu 16.04 LTS</br>
Ubuntu 14.04 LTS</br>


# Deployment process

**Prerequisite**:</br>
  - You need the following AWS permissions:
	- AWSOpsWorksFullAccess
	- permission to create, modify, read, list and delete IAM Policies and Roles.
  - If you need to join the AWS instances to Active Directory, you also need the followings:</br>
	- permission to create and upload files to a S3 bucket.
    - access to a Linux/Unix machine that has Centrify Server Suite installed and is connected to the Active Directory.  
	  You need to be able to run the adkeytab command on the machine.
    - an Active Directory user who is used to automatically join EC2 instance for Linux to your Centrify zone
    and you need to make sure that the user has following two permissions at least:</br>
	 - "Join computers to the zone".  This can be granted using "DirectManage Access Manager".
	 - "Join a comptuer to the domain".  This can be granted using "Active Directory Users and Computers" tool.</br>
	 Note that this user should not have any other permissions, and does not need the permission to login to any system.
    

**Start to deploy**:</br>
  1. If you do not need to join the AWS instance to Active Directory, you can skip directly to step 3.
     
	 You need to create a login.keytab file for the user who will join the AWS instances to Active Directory.   
	 Use the following command on your Linux/Unix system that is already joined to Active Directory:</br>
     ```
     adkeytab -A -K login.keytab -u your_admin -p your_admin_password AD_user_to_join
     ```
     </br>'your_admin'/'your_admin_password' are separately an administrator and its password of Active Directory.</br>
     AD_user_to_join is the Active Directory user who will join the AWS instance to Active Directory. For example:</br>
     adkeytab -A -K login.keytab -u admin1  -p admin1_pass join_user1

  2. You need to sign in https://console.aws.amazon.com/s3 and create a S3 bucket and then upload 
     login.keytab file. Please refer to
     http://docs.aws.amazon.com/AmazonS3/latest/gsg/CreatingABucket.html about how to create a bucket.

  3. Create an IAM policy for use by IAM role for the instances created by OpsWorks.</br>
     If the AWS instance needs to join to Active Directory, the IAM instance needs to access the login.keytab file in the S3 bucket.  
	 The following is an example of the policy:
     ```
	{
		"Version": "2012-10-17",
		"Statement": [ 
			{
			"Effect":"Allow",
			"Action":[
				"s3:GetObject",
				"s3:ListObject"
			],
			"Resource":[ "arn:aws:s3:::your_s3_bucket/login.keytab" ]
			},
			{
			"Action": ["ec2:*",
				"iam:PassRole",
				"cloudwatch:GetMetricStatistics",
				"cloudwatch:DescribeAlarms",
				"ecs:*",
				"elasticloadbalancing:*",
				"rds:*"],
			"Effect": "Allow",
			"Resource": ["*"] 
			}
		]
	}
     ```
     </br> You shall replace 'your_s3_bucket' with your own bucket mentioned in Step 2.
	 </br>
	 If the AWS instance does not need to join to Active Directory, you can this use as the policy:</br>
     ```
	 {
		"Version": "2012-10-17",
		"Statement": [ 
			{
			"Action": ["ec2:*",
				"iam:PassRole",
				"cloudwatch:GetMetricStatistics",
				"cloudwatch:DescribeAlarms",
				"ecs:*",
				"elasticloadbalancing:*",
				"rds:*"],
			"Effect": "Allow",
			"Resource": ["*"] 
			}
		]
	}
     ```
  4. Create an IAM role to grant EC2 instances to access AWS resources.
     - Select Amazon EC2 as AWS Service role type while creating the IAM role.
     - Associate the IAM policy created in step 3 with the IAM role.
     - Choose the Trust Relationships tab, and then choose Edit Trust Relationship.
     - Modify the trust policy as follows:</br>
    ```
	 {
		"Version": "2012-10-17",
		"Statement": [
			{
			"Effect": "Allow",
			"Principal": {
			"Service": [
			"opsworks.amazonaws.com",
			"ec2.amazonaws.com"
			]},
		"Action": "sts:AssumeRole"
		}]
	} 
    ```
	 
  5. Create your Key Pair if you don't have one so that you can log into your EC2 instances. You can refer to</br>
      http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair about 
      how to create Key Pair.

  6. You need to create a Chef-12 Stack, please refer to:</br>
     http://docs.aws.amazon.com/opsworks/latest/userguide/gettingstarted-linux.html </br>
     Please notice:</br>
     - On VPC box, you must select your own VPC and make sure that you are able to access internet by your Default subnet.
     - On Default SSH key list box, select your own Key Pair mentioned in Step 5.
     - On Use custom Chef cookbooks, select yes.
         - On Repository type list box, select Git.
         - On Repository URL, type 'https://github.com/centrify/AWS-Opsworks.git'
     - Click Advanced link and make sure:
         - On IAM role box, select the IAM role you created in Step 4.
         - On Default IAM instance profile box, select your IAM role created in Step 4.
         - On Custom JSON box, type your own JSON attributes.  
	</br>
	Following is an example of Custom JSON:</br>
           ```
	{
		"CENTRIFY_REPO_CREDENTIAL":"XXXX111111111111111111111XXX22%40centrify:3333333333333333333333444444444444444444",
		"CENTRIFYCC_TENANT_URL": "myurl.centrify.com",
		"CENTRIFYCC_ENROLLMENT_CODE": "88888888-4000-1000-0444-88888888",
		"CENTRIFYCC_AGENT_AUTH_ROLES": "Agent_loginrole1",
		"CENTRIFYCC_FEATURES": "aapm,agentauth",
		"CENTRIFYCC_NETWORK_ADDR_TYPE": "PrivateIP",
		"CENTRIFYCC_COMPUTER_NAME_PREFIX": "",
		"CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS": "--resource-setting ProxyUser:centrify",
		
		"CENTRIFYDC_JOIN_TO_AD": "yes",
		"CENTRIFYDC_ZONE_NAME": "zone2",
		"CENTRIFYDC_KEYTAB_S3_BUCKET": "centrify-bucket",
		"CENTRIFYDC_ADDITIONAL_PACKAGES": "centrifydc-openssh centrifydc-ldapproxy",
		"CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS": "--ldap --verbose"
	} 
           ```
           </br>See the section "Deployment Scenario" on which attributes need to be changed for each deployment scenario.
		You can replace above attributes by referring to later 'Explaining Attributes of Custom JSON' section.

  7. Add a Layer for your Stack and enter your Layers page:
     - Switch to Recipes tab.</br>
	   - Add the following to the Setup box: </br>
	      - If only join to Active Directory: "centrify_agents::deploy_centrifydc" 
		  - If only enroll to Centrify Identity Platform:  "centrify_agents::deploy_centrifycc"
		  - If both join to Active Directory and enroll to Centrify Identity Platform: 
				"centrify_agents::deploy_centrifydc" and "centrify_agents::deploy_centrifycc"
        </br>
	   - Add the following to the Shutdown down:
	   	  - If only join to Active Directory: "centrify_agents::undeploy_centrifydc" 
		  - If only enroll to Centrify Identity Platform:  "centrify_agents::undeploy_centrifycc"
		  - If both join to Active Directory and enroll to Centrify Identity Platform: 
				"centrify_agents::undeploy_centrifydc" and "centrify_agents::undeploy_centrifycc"
		</br>
	 - Switch to Network tab and set Public IP addresses to yes.
     - Switch to Security tab and choose the role created in step 4 as EC2 instance profile listbox.

  8. Add Instances for your Layer.

  9. Start/Stop your instances.

# Deployment Scenario

Scenario 1.    Install CentrifyDC and adjoin to AD:</br>
  - Click Stack Settings and modify Custom JSON as follows:</br>
    a. Set CENTRIFY_REPO_CREDENTIAL to your username-password of Centrify Repository.</br>
    b. Set CENTRIFYDC_JOIN_TO_AD to yes.</br>
    c. Set CENTRIFYDC_KEYTAB_S3_BUCKET to the S3 bucket where you put the login.keytab file.</br>
    d. Set CENTRIFYDC_ZONE_NAME to your zone name which you want to join.
  - Enter Layers->Recipes page.</br>
    e. In Setup box, type centrify_agents::deploy_centrifydc.</br>
    f. In Shutdown box, type centrify_agents::undeploy_centrifydc.

Scenario 2.    Install CentrifyCC and enroll to Centrify identity platform:
  - Click Stack Settings and modify Custom JSON as follows:</br>
    a. Set CENTRIFYCC_TENANT_URL to your tenant URL.</br>
    b. Set CENTRIFYCC_ENROLLMENT_CODE to your enrollment code.</br>
    c. Set CENTRIFYCC_AGENT_AUTH_ROLES to your authentication roles.</br>
    d. Set CENTRIFYCC_FEATURES to your enabled features of cenroll.
  - Enter Layers->Recipes page.</br>
    e. In Setup box, type centrify_agents::deploy_centrifycc.</br>
    f. In Shutdown box, type centrify_agents::undeploy_centrifycc.

Scenario 3.    Install CentrifyCC and CentrifyDC, run cenroll and adjoin
  - Click Stack Settings and modify Custom JSON as follows:</br>
    Repeat Step a~d of Scenario 1 and Step a~d of Scenario 2.
  - Eneter Layers->Recipes page.</br>
    In Setup box, set the recipes to centrify_agents::deploy_centrifydc and centrify_agents::deploy_centrifycc.</br>
    In Shutdown box, set the recipes to centrify_agents::undeploy_centrifydc and centrify_agents::undeploy_centrifycc.
 

# Explaining Attributes of Custom JSON
		
		CENTRIFY_REPO_CREDENTIAL:
		// The user name and password required to access Centrify repository.  Cannot be empty.
		
		CENTRIFYCC_TENANT_URL: 
		// The CIP instance to enroll to.  Cannot be empty.
		
		CENTRIFYCC_ENROLLMENT_CODE: 
		// The enrollment used to enroll.  Cannot be empty.
		
		CENTRIFYCC_AGENT_AUTH_ROLES: 
		// Specify the CIP roles (as a comma separated list) where members can log in to the instance.
		// Cannot be empty.
		
		CENTRIFYCC_FEATURES
		// Specify the features (as a comma separated list) to enable in cenroll CLI.
		// Cannot be empty.
		
		CENTRIFYCC_NETWORK_ADDR_TYPE: 
		//Specify what to use as the network address in created CPS resource.   
		// Allowed values:  PublicIP, PrivateIP, HostName.  Default: PublicIP
		
		CENTRIFYCC_COMPUTER_NAME_PREFIX: 
		// Specify the prefix to use as the hostname in CPS.   
		// The hostname will be shown as <prefix>-<hostname> in CPS.
		// If it is empty, then cenroll will use <hostname> instead.
		
		CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS: 
		// This specifies which addtional options will be used.
		// Default we will use following options to cenroll:
		//  /usr/sbin/cenroll \
		//       --tenant "CENTRIFYCC_TENANT_URL" \
		//       --code "CENTRIFYCC_ENROLLMENT_CODE" \
		//       --agentauth "CENTRIFYCC_AGENT_AUTH_ROLES" \
		//       --features "CENTRIFYCC_FEATURES" \
		//        --name "CENTRIFYCC_COMPUTER_NAME_PREFIX-<hostname>" \
		//        --address "NETWORK_ADDR"
		//
		// The options shall be list(separated by space) such as '--resource-setting ProxyUser:centrify' .
		
		CENTRIFYDC_JOIN_TO_AD: 
		// This specifies whether the agent will join to on-premise Active Directory directly. 
		// Allowed value: yes/no (default: yes)
		
		CENTRIFYDC_ZONE_NAME: 
		// The name of the zone to join to.  Cannot be empty.
		
		CENTRIFYDC_KEYTAB_S3_BUCKET: 
		//This specifies a s3 bucket to download the login.keytab that has the credential of 
		// the user who joins the computer to AD. Note that the startup script will use AWS CLI
		// to download this file.   Cannot be empty.
		
		CENTRIFYDC_ADDITIONAL_PACKAGES: 
		// This specifies whether to install additional Centrify packages. 
		// The package names shall be separated by space.
		// Allowed value: centrifydc-openssh centrifydc-ldapproxy (default: none).
		// For example: CENTRIFYDC_ADDITIONAL_PACKAGES="centrifydc-openssh centrifydc-ldapproxy"
		
		CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS:
		// This specifies additional adjoin options.
		// The additional options shall be a list separated by space.
		// Default we will run adjoin with following options:
		// /usr/sbin/adjoin $domain_name -z $CENTRIFYDC_ZONE_NAME --name `hostname`

# FAQ

Q. Can I specify my own --name parameter for cenroll?

Yes. You can specify your prefix of --name in parameter 'CENTRIFYCC_COMPUTER_NAME_PREFIX'.
The centrifycc.sh will form a computer name using 
<CENTRIFYCC_COMPUTER_NAME_PREFIX parameter>-<hostname> while running cenroll.

Q. Can I only install CentrifyDC but not join to AD?

Yes. You need to set CENTRIFYDC_JOIN_TO_AD to no and repeat Step e,f of Scenario 1.

Q. Can I specify additional options for adjoin or cenroll?

Yes. You can specify additional options in parameter CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS
or CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS.

Q. Can I specify what to use as the network address in created CPS resource?

Yes. You can set parameter CENTRIFYCC_NETWORK_ADDR_TYPE to specify public
IP(set to PublicIP), private IP(set to PrivateIP), or host name(set to HostName)
as your network address in CPS resource.

Q. Why don't I get Public IP while enroll EC2 for Linux to Centrify identity?

You shall make sure that your Default subnet in Stack  has enabled public IP assignment and
set CENTRIFYCC_NETWORK_ADDR_TYPE to yes if you want to use public IP as your
address while running cenroll. 

Q. What does error "x509: certificate signed by unknown authority" mean?

Your computer needs to be enrolled to Centrify identity platform, but none of
the server certificates can be verified. Certificate problems may indicate
potential security risks. Please contact your administrator to configure the
root CA certificate.
References:
https://centrify.force.com/support/Article/KB-7973-How-to-configure-Linux-machine-trusted-certificate-chain-to-perform-enrollment-for-Centrify-Agent

Q. How to use "user data" to run orchestration script on AWS instances?

From AWS documentation:

"Scripts entered as user data are executed as the root user, so do not use the
sudo command in the script. Remember that any files you create will be owned by
root; if you need non-root users to have file access, you should modify the
permissions accordingly in the script. Also, because the script is not run
interactively, you cannot include commands that require user feedback (such as
yum update without the -y flag)." [1]

"User data is limited to 16 KB." [2]

References:
[1] Running Commands on Your Linux Instance at Launch
http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html

[2] Instance Metadata and User Data
http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html


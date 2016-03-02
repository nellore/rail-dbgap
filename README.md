# Rail-dbGaP

The [National Institutes of Health (NIH)](http://www.nih.gov) maintains security [requirements](https://gds.nih.gov/) and [recommmendations](http://www.ncbi.nlm.nih.gov/projects/gap/pdf/dbgap_2b_security_procedures.pdf) for analyzing controlled-access genomic data, including [dbGaP](http://www.ncbi.nlm.nih.gov/gap)-protected data. Rail-dbGaP is a protocol described in [this preprint](http://j.mp/rail-dbgap) for securely analyzing dbGaP-protected genomic data from the [Sequence Read Archive (SRA)](http://www.ncbi.nlm.nih.gov/sra) in the cloud with [Amazon Elastic MapReduce (EMR)] in a manner compliant with NIH guidelines. The protocol is implemented in [Rail-RNA](http://rail.bio/), software for scalable analysis of many hundreds of RNA sequencing (RNA-seq) samples. A step-by-step guide for setting up Rail-RNA to analyze dbGaP-protected RNA-seq data is provided in the Rail documentation [here](http://docs.rail.bio/dbgap/); the present document contains a [technical specification](README.md#spec) of the Rail-dbGaP protocol and [walks the user](README.md#kmer) through an example implementation that counts the number of input samples (i.e., [SRA run accession numbers](http://www.ncbi.nlm.nih.gov/books/NBK56913/#search.what_do_the_different_sra_accessi)) in which each k-mer present in at least one read from among the samples appears. A preprint describing the Rail-dbGaP protocol is available [here](http://j.mp/rail-dbgap).

## MapReduce and Elastic MapReduce

The [MapReduce](https://en.wikipedia.org/wiki/MapReduce) programming model divides a problem into a sequence of alternating computation and aggregation steps. Each step is performed by distributing independent tasks across workers in a cluster of computers. [Elastic MapReduce (EMR)](https://aws.amazon.com/elasticmapreduce/) is a [Hadoop](http://hadoop.apache.org/)-based implementation of MapReduce especially for a cluster of [Elastic Compute Cloud (EC2)](https://aws.amazon.com/ec2/) instances, or virtualized computers, on [Amazon Web Services](https://aws.amazon.com/), a commercial cloud provider. EMR reads input from the web and/or Simple Storage Service (S3), Amazon's cloud storage service, and writes its output back to S3.

<a id="spec"></a>
## Rail-dbGaP protocol specification

Rail-dbGaP secures an EMR cluster so it is compliant with NIH guidelines as follows. (See Figure 1 of the [preprint](http://j.mp/rail-dbgap) for an illustration. The sections [Setting up Amazon Web Services](README.md#setup) and [Studying k-mers in dbGaP-protected samples with EMR](README.md#kmer) put together protocol elements to show their implementation explicitly.)

1. **The cluster is created within a subnet of a [Virtual Private Cloud (VPC)](https://aws.amazon.com/vpc/)**, a logically isolated unit of the cloud providing a private network and firewall. The connection with S3 is via a ``VPC endpoint,'' which ensures that data transferred never leaves the data center. Each instance has a public IP. The VPC is set up by creating a stack with the [CloudFormation](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) template [`cloudformation/dbgap.template`](cloudformation/dbgap.template).

2. **Inbound traffic to the cluster is restricted via security groups.** A security group is essentially a stateful firewall. A master security group for the master instance and a worker security group for worker instances prevent initiation of any connection to the cluster except by essential web services. These web services correspond to particular IPs and ports, and the most restrictive sets for master and worker instances are configured automatically. SSH access to the cluster is also restricted: the only interaction between user and cluster is via the EMR interface, which presents progress information through the essential web services. Security groups are also set up by creating a stack with the [CloudFormation](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) template [`cloudformation/dbgap.template`](cloudformation/dbgap.template). Master and worker instances must be associated with security groups when creating the EMR cluster.

3. **Data are encrypted at rest.** During cluster setup, before any sensitive data has reached the cluster, each instance runs the preliminary script (i.e., bootstrap action) [`bootstraps/encrypt_local_storage.sh`](https://github.com/nellore/rail-dbgap/blob/master/bootstraps/encrypt_local_storage.sh) that uses [Linux Unified Key Setup (LUKS)](https://guardianproject.info/code/luks/) to create an encrypted partition with a keyfile. The key is randomly generated on each instance and never exposed to the user. Temporary files, the Hadoop distributed file system, and buffered output to the cloud storage service are all configured to reside on the encrypted partition via symbolic links. (See line 128 of [`bootstraps/encrypt_local_storage.sh`](https://github.com/nellore/rail-dbgap/blob/master/bootstraps/encrypt_local_storage.sh).) Files written to cloud storage are also encrypted; Amazon S3 uses [AES256](https://en.wikipedia.org/wiki/Advanced_Encryption_Standard). This is enforced by the creation of a bucket with a policy barring uploads that do not turn on server-side encryption in the dbGaP template [`cloudformation/dbgap.template`](cloudformation/dbgap.template).

4. **Data are encrypted in transit.** Worker instances download dbGaP data using [SRA Tools](http://ncbi.github.io/sra-tools/), ensuring encryption of data transferred from dbGaP to the cluster. Secure Sockets Layer (SSL) is enabled for transfers between cloud storage and the cluster as well as between cloud storage service and compliant local storage to which an investigator saves results. This is achieved by setting the EMRFS configuration parameter `fs.s3.enableServerSideEncryption=true`.

5. **Identities are managed to enforce the principle of least privilege.** The principle of least privilege prescribes users have only the privileges required to perform necessary tasks. In the Rail-dbGaP protocol, an administrator grants the user only those privileges required to run Hadoop programs on EMR clusters. The administrator uses multi-factor authentication and constrains the user to set up a password satisfying NIH's requirements listed among [security best practices](http://www.ncbi.nlm.nih.gov/projects/gap/pdf/dbgap_2b_security_procedures.pdf) (minimum of 12 characters, no complete dictionary words, etc.) On AWS, an account administrator configures an Identity and Access Management (IAM) user expressly for running Hadoop jobs and retrieving results from S3, and the password rules described above are enforced. This is achieved as described below in [AWS account setup]().

6. **Audit logs are enabled.** These record logins and actions taken by the user and on the user's behalf, including API calls made by processes running on the cluster. On AWS, audit logs take the form of CloudTrail logs stored in encrypted S3 buckets. They are enabled when a stack is created with the dbGaP template [`cloudformation/dbgap.template`](cloudformation/dbgap.template).

<a id="setup"></a>
## Setting up Amazon Web Services

The steps below create a new [AWS IAM](https://aws.amazon.com/iam/) account especially for analyzing dbGaP-protected data. To perform these steps, both user and AWS site administrator should be available. (For many investigators, user and administrator will be the same person.) It is recommended that they are physically together to minimize passing of credentials. Before continuing, the user should install the [AWS Command Line Interface (CLI)](https://aws.amazon.com/cli/). Optionally, the user may also have [requested access](https://dbgap.ncbi.nlm.nih.gov/aa/dbgap_request_process.pdf) to some dbGaP-protected sample on the [Sequence Read Archive](http://www.ncbi.nlm.nih.gov/sra) (SRA) and received a key file with an `ngc` extension.

### Set up an administrator account (administrator)

These steps should be performed if the site administrator is new to AWS.

1. Navigate to [http://aws.amazon.com/free](http://aws.amazon.com/free) in your web browser.
2. Click **Create a free account**.
3. Check the **I am a new user** box and and continue to follow the instructions to create your new account. You'll enter, for example, contact and payment information. Note that the **Basic** level of service is sufficient for our purposes.
4. Make a note of your account number.
    1. Log into the [AWS console] using the new account's email address and password.
    2. Click on the arrow next to your user name in the gray banner at the top of the page.
    3. Select **My Account**, and the **Account Id** will be displayed at the top of the page.
5. Secure the account
    1. Log into the [AWS console](https://aws.amazon.com/console/) using the new account's email address and password.
    2. Open the **Identity and Access Management** page.
    <div align="center"><img src="assets/iammenu.png" alt="Select IAM" style="width: 300px; padding: 5px;"/></div>
    3. Under **Security Status**, click **Activate MFA on your root account**, then click **Manage MFA**, and follow the instructions to enable multi-factor authentication. We use a virtual MFA device (smartphone) with Google Authenticator.
     <div align="center"><img src="assets/mfa.png" alt="Manage MFA" style="width: 400px; padding: 5px;"/></div>
    * Under **Apply an IAM password policy**, click **Manage Password Policy**.
    <div align="center"><img src="assets/managepasspolicy.png" alt="Manage Password Policy" style="width: 450px; padding: 3px;"/></div>
    Configure the password policy according to the requirements mentioned in the [NIH Security Best Practices for Controlled-Access Data Subject to the NIH Genomic Data Sharing (GDS) Policy](http://www.ncbi.nlm.nih.gov/projects/gap/pdf/dbgap_2b_security_procedures.pdf). This usually entails the following, but please note that your institution may impose more stringent requirements:
        * Requiring a minimum password length of 12
        * Requiring at least one uppercase letter
        * Requiring at least one lowercase letter
        * Requiring at least one number
        * Requiring at least one non-alphanumeric character
        * Enable password expiration after 120 days
    <div align="center"><img src="assets/passpolicy.png" alt="Password policies" style="width: 450px; padding: 5px;"/></div>
    * Click **Apply password policy**.

### Set up a new IAM user (administrator & user)

During this process, it is best for the account administrator to sit with the user to minimize passing credentials. 

1. *Administrator:* create new IAM user.
    1. From the new user's computer, log into the [AWS Console](https://aws.amazon.com/console/) and select **Identity and Access Management**.
    2. Click **Users** on the left pane, then **Create New Users** on the right pane.
    <div align="center"><img src="assets/createnew.png" alt="Create New Users" style="width: 450px; padding: 5px;"/></div>
    3. Enter the new user's username. We call the new user **dbgapuser** in the screenshot. Check the **Generate an access key for each user** checkbox, and click **Create**.
    <div align="center"><img src="assets/genaccesskey.png" alt="Generate access key" style="width: 600px; padding: 5px;"/></div>
    4. Click **Download Credentials**. These credentials (*credentials.csv*) include the AWS Access Key ID and AWS Secret Access Key. It is recommended that the file containing the credentials be made readable only by the user immediately. The credentials should never be shared, intentionally or inadvertently, with anyone else.

2. *User:* register credentials with the AWS CLI by entering
        
        aws configure --profile dbgap
at a terminal prompt on the user's computer. Enter the AWS Access Key ID, AWS Secret Access Key, and a default region as prompted. We recommend using the `us-east-1` because its connection to dbGaP-protected data on SRA appears to be fastest. A default output format need not be specified. Now the new user can issue AWS API calls via the AWS CLI. *It is recommended that credentials file that was just downloaded is now deleted.*

3. *Administrator:* Set user's password.
    1. Return to the [AWS Console](https://aws.amazon.com/console/), again click **Identity and Access Management**, again click **Users** on the left sidebar, and select the new user. Under **User Actions**, click **Manage Password**.
    <div align="center"><img src="assets/managepass.png" alt="Manage Password" style="width: 600px; padding: 5px"/></div>
    2. Select **Assign an auto-generated password**, check the **Require user to create a new password at next sign-in** box, and click **Apply**.
    <div align="center"><img src="assets/autogenpass.png" alt="Password assignment" style="width: 600px; padding: 5px"/></div>
    3. Click **Download Credentials**. The new credentials file *credentials (2).csv* contains the username, the auto-generated password, and the URL for the account-specific login page.

4. *User:* navigate to the login page URL from *credentials (2).csv*, log in, and change the password as prompted.
<div align="center"><img src="assets/oldnewpass.png" alt="Change password" style="width:400px; padding: 5px"/></div>

<a id="cloudform"></a>
### Create a secure CloudFormation stack (administrator)

[CloudFormation](https://aws.amazon.com/cloudformation/) facilitates creation and management of a group of related AWS resources. Rail-dbGaP provides CloudFormation template for creating a [Virtual Private Cloud](https://aws.amazon.com/vpc/) (VPC) with a [single public subnet](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Scenario1.html). An EMR job flow that analyzes dbGaP data should be launched into this subnet. The VPC is supplemented by several security features, including

* a VPC endpoint for S3, which ensures that the connection between the Elastic MapReduce cluster and S3 is private.
* security groups that block all inbound traffic to the cluster from the internet except from the Elastic MapReduce webservice.
* the creation of a secure bucket on S3 into which Rail-RNA should write all its output when operating on dbGaP-protected data. The bucket has an attached policy barring uploads that do not have server-side encryption (AES256) turned on.
* [CloudTrail](https://aws.amazon.com/cloudtrail/) logs recording AWS API calls. These are written to the secure bucket.

The administrator should grab the latest version of the template [here](https://raw.githubusercontent.com/nellore/rail/master/src/cloudformation/dbgap.template). Implement it by following these steps. (If the administrator already has CloudTrail turned on, they may not work, causing a rollback. An administrator satisfied with their CloudTrail configuration may instead want to use [this alternative CloudFormation template](https://raw.githubusercontent.com/nellore/rail/master/src/cloudformation/dbgap_minus_cloudtrail.template), which creates the VPC but does not attempt to set up CloudTrail.)

1. Click **CloudFormation** in the AWS console, making sure the region in the upper-right corner of the screen is the same as the user's default region (typically `us-east-1`, i.e., N. Virginia).
<div align="center"><img src="assets/cloudformconsole.png" alt="Select CloudFormation" style="width: 300px; padding: 5px"/></div>
2. Click **Create Stack**.
<div align="center"><img src="assets/createstack.png" alt="Create Stack" style="width: 700px; padding: 5px"/></div>
3. Under **Choose a template**, opt to upload `dbgap.template` to Amazon S3, and click **Next**.
<div align="center"><img src="assets/choosetemplate.png" alt="Choose template" style="width: 600px; padding: 5px"/></div>
4. On the next screen:
    * Next to **Stack name**, write "dbgap".
    * Next to **Parameters**, let the user type the name of a secure bucket into which they will write all of Rail-RNA's output. The bucket name should not have been taken by any other S3 user.
<div align="center"><img src="assets/makeupbucket.png" alt="Pick bucket name" style="width: 600px; padding: 5px"/></div>
5. Click **Next** and **Next** again, then click **Create** and wait for the stack creation to complete. The status message "CREATE_COMPLETE" will soon appear next to "dbgap" on the list of stacks.
<div align="center"><img src="assets/createcomplete.png" alt="CREATE_COMPLETE" style="width: 600px; padding: 5px"/></div>

The best defense is a good offense, and you are encouraged to monitor traffic to clusters launched by the user. You may want to explore turning on [VPC flow logs](https://aws.amazon.com/blogs/aws/vpc-flow-logs-log-and-view-network-traffic-flows/) and [CloudWatch alarms](http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/AlarmThatSendsEmail.html) for suspicious activity.

### Delegate Elastic MapReduce and CloudFormation authorites to the new IAM user (administrator)

The new IAM user still needs sufficient privileges to run Rail-RNA on Elastic MapReduce.

1. Return to the [AWS Console](https://aws.amazon.com/console/), again click **Identity and Access Management**, but now click **Policies** on the left sidebar.
2. Click **Create Policy**, then select **Create Your Own Policy**. (You may need to click **Get Started** first.)
    1. Under **Policy Name**, enter "UseExistingEMRRoles".
    2. Under **Policy Document**, paste the following.

            {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                             "iam:GetInstanceProfile",
                             "iam:GetRole",
                             "iam:PassRole"
                        ],
                        "Resource": "*"
                    }
                ]
            }

    3. Click **Create Policy**.
    <div align="center"><img src="assets/policydoc.png" alt="Create Policy" style="width: 700px; padding: 5px"/></div>
3. Now click **Users** in the left pane, select the new IAM user, and click the **Permissions** tab.
<div align="center"><img src="assets/permissionstab.png" alt="Permissions" style="width: 700px; padding: 5px"/></div>
4. Click **Attach Policy**, and select the `AWSCloudFormationReadOnlyAccess`, `AmazonElasticMapReduceFullAccess`, and `UseExistingEMRRoles` policies. Then click Attach Policy.
<div align="center"><img src="assets/afterpermissionstab.png" alt="Attach Policy" style="width: 700px; padding: 5px"/></div>
Different policies including only some of the permissions from these may be included, but note that the user must be able to:
        * launch Elastic MapReduce clusters into the VPC from the secure dbGaP CloudFormation stack created by the administrator above, and
        * read and write to the secure S3 bucket created by the administrator on behalf of the user.

### Set up default EMR roles (administrator & user)

1. *Administrator:* follow [these instructions](http://docs.aws.amazon.com/ElasticMapReduce/latest/DeveloperGuide/emr-iam-roles-creatingroles.html) to create default roles for Elastic MapReduce.
2. *User:* run

        aws emr create-default-roles --profile dbgap
to retrieve the default Elastic MapReduce roles created by the administrator.

<a id="kmer"></a>
## Studying k-mers in dbGaP-protected samples with EMR

This section reviews the implementation of an EMR pipeline that ingests dbGaP-protected data and counts the number of samples in which each *k*-mer found in least one read across samples appears. [dbGaP support](https://dbgap.ncbi.nlm.nih.gov/aa/wga.cgi?page=login) has kindly provided a dataset composed of public RNA-seq samples from [1000 Genomes](http://www.1000genomes.org/) exclusively for testing secure cloud-based pipelines. Its project accession number on SRA is [SRP041052](http://trace.ncbi.nlm.nih.gov/Traces/sra/?study=SRP041052), and the steps below use three samples from it.

Assume the secure bucket created during [AWS setup](README.md#setup) is at `s3://rail-dbgap-secure`. The following is performed on the user's computer, where the AWS CLI was installed.

1. Download [the dbGaP repository key](ftp://ftp.ncbi.nlm.nih.gov/sra/examples/decrypt_examples/prj_phs710EA_test.ngc) for the test data. Now upload the key to S3 securely with the AWS CLI by entering

        aws s3 cp /path/to/prj_phs710EA_test.ngc s3://rail-dbgap-secure/test/prj_phs710EA_test.ngc
You may choose to delete the key from your computer with

        rm /path/to/prj_phs710EA_test.ngc
2. Sign into AWS 
2. Run

        rail-rna go elastic
          -a hg38
          -o s3://this-is-a-bucket-name-the-user-makes-up/dbgaptest
          -c 1
          -m https://raw.githubusercontent.com/nellore/rail/master/ex/secure.manifest
          --secure-stack-name dbgap
          --profile dbgap
          --dbgap-key /path/to/prj_phs710EA_test.ngc

to submit a secure job flow into the public subnet of the VPC created above that preprocesses and aligns the test sample. Use the EMR interface to monitor the progress of the job flow, and check the bucket `s3://this-is-a-bucket-name-the-user-names-up/dbgaptest` for results after it's done.

### Analyze dbGaP-protected data

The user may now submit Rail-RNA jobs that analyze dbGaP-protected data from their computer. A line in a manifest file (as described in the [tutorial](tutorial.md) and [reference](reference.md)) corresponding to a dbGaP-protected sample has the following format.
```
dbgap:<SRA run accession number>(tab)0(tab)<sample label>
```
where a run accession number from SRA begins with `SRR`, `ERR`, or `DRR`. An example manifest file is the [test manifest file](https://raw.githubusercontent.com/nellore/rail/master/ex/secure.manifest) used in the previous section. Every Rail-RNA command analyzing dbGaP data should include the command-line parameters `--secure-stack-name dbgap --profile dbgap --dbgap-key [the key file with the NGC extension you download]` and should write to the secure bucket created by the administrator. An example command follows.
```
rail-rna go elastic
  -m dbgap.manifest
  -a hg38
  -o s3://this-is-a-bucket-name-the-user-makes-up/dbgapout
  -c 1
  --secure-stack-name dbgap
  --profile dbgap
  --dbgap-key /path/to/some_dbgap_key.ngc
```
Rail-RNA does not currently support analyzing TCGA data.

### Helpful notes for administrators

As for any new AWS account, you should consider how you would like to configure billing.  [Consolidated billing](http://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/consolidated-billing.html) can be convenient if you are managing multiple AWS accounts simultaneously.

Further, you should consider raising your EC2 instance limits.  This is particularly important if you plan to analyze large datasets (more than 100 RNA-seq samples at a time).  To raise your limits, visit [this page](http://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

/// Matches the skill names found in a user's CV analysis (for example
/// "SQL" or "Microsoft Power BI") with the skill names stored on
/// certifications (for example "Databases and SQL").
///
/// Claude writes skill gaps as short free-text names taken from job
/// postings, while the certification dataset uses a fixed list of 87 skill
/// names. This class bridges the two:
///  1. [normalize] lower-cases a name and removes punctuation.
///  2. [canonical] replaces a known synonym (SQL, MySQL, T-SQL ...) with the
///     certification skill name it belongs to (Databases and SQL).
///  3. [matches] compares two names: equal after step 2, or one name
///     contains all the words of the other (two words or more).
///  4. A specific product or technology (React, Node.js, Tableau, Django
///     ...) only counts when the certification itself mentions it. Knowing
///     that a certification teaches "JavaScript" is not enough to say it
///     covers a "Node.js" gap.
class SkillMatcher {
  SkillMatcher._();

  /// Lower-case, '&' becomes "and", everything except letters and digits
  /// becomes a single space. "CI/CD" -> "ci cd", "T-SQL" -> "t sql".
  static String normalize(String input) {
    final lower = input.toLowerCase().replaceAll('&', ' and ');
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  /// The certification skill name (normalized) that [input] stands for.
  static String canonical(String input) {
    final key = normalize(input);
    return _aliases[key] ?? key;
  }

  /// True when the two skill names mean the same thing.
  static bool matches(String a, String b) {
    final ca = canonical(a);
    final cb = canonical(b);
    if (ca.isEmpty || cb.isEmpty) return false;
    if (ca == cb) return true;

    final ta = _tokens(ca);
    final tb = _tokens(cb);
    final shorter = ta.length <= tb.length ? ta : tb;
    final longer = ta.length <= tb.length ? tb : ta;
    // A single word is too vague to match by containment
    // ("cloud" must not match "cloud security").
    if (shorter.length < 2) return false;
    return shorter.every(longer.contains);
  }

  /// The entries of [wanted] (for example the user's skill gaps) that are
  /// covered by at least one entry of [available] (the certification skills).
  /// [evidence] is the certification's own text (name, description, skills):
  /// specific technologies must appear there, and multi-word names found
  /// there count as covered too.
  /// The original spelling of [wanted] is kept; each entry appears once.
  static List<String> matchedSkills(
    List<String> wanted,
    List<String> available, {
    String evidence = '',
  }) {
    final text = ' ${normalize(evidence)} ';
    final result = <String>[];
    for (final item in wanted) {
      if (result.contains(item)) continue;
      final key = normalize(item);
      if (key.isEmpty) continue;
      final bool covered;
      if (_specific.contains(key)) {
        covered = _mentions(text, key) ||
            available.any((skill) => normalize(skill) == key);
      } else {
        covered = available.any((skill) => matches(item, skill)) ||
            (_tokens(key).length >= 2 && _mentions(text, key));
      }
      if (covered) result.add(item);
    }
    return result;
  }

  /// True when the padded, normalized [text] contains [key] as whole words
  /// (also "nodejs" / "node" for "node js").
  static bool _mentions(String text, String key) {
    final variants = <String>{key, key.replaceAll(' ', '')};
    // "react js", "reactjs" and "react" name the same thing
    final base = key.endsWith(' js')
        ? key.substring(0, key.length - 3)
        : (key.endsWith('js') && !key.contains(' ')
            ? key.substring(0, key.length - 2)
            : null);
    if (base != null && base.isNotEmpty) {
      variants.add('$base js');
      if (base.length >= 4) variants.add(base);
    }
    return variants.any((v) => v.isNotEmpty && text.contains(' $v '));
  }

  /// Products, frameworks and tools: they belong to a broader skill (Node.js
  /// is JavaScript, Tableau is Data Visualization), but a certification on
  /// the broader skill does not necessarily teach them.
  static final Set<String> _specific = {
    for (final name in const [
      'MySQL', 'PostgreSQL', 'Postgres', 'T-SQL', 'PL/SQL', 'SQL Server',
      'Microsoft SQL Server', 'Oracle SQL', 'Oracle Database', 'SQLite',
      'Tableau', 'Looker', 'Qlik', 'QlikView', 'Qlik Sense',
      'Scikit-learn', 'Sklearn', 'TensorFlow', 'PyTorch', 'Keras', 'ChatGPT',
      'Pandas', 'NumPy',
      'Node.js', 'NodeJS', 'TypeScript',
      'React', 'React.js', 'ReactJS', 'Angular', 'Vue', 'Vue.js', 'VueJS',
      'Next.js', 'Tailwind CSS', 'Bootstrap',
      'Express', 'Express.js', 'Django', 'Flask', 'Spring Boot', 'Laravel',
      'ASP.NET', '.NET', 'GraphQL',
      'GCP', 'Google Cloud', 'Google Cloud Platform',
      'Podman', 'EKS', 'AKS', 'GKE',
      'Terraform', 'Ansible', 'CloudFormation', 'Bicep', 'Pulumi', 'Puppet',
      'Chef', 'Jenkins', 'GitHub Actions', 'GitLab CI',
      'Red Hat', 'RHEL', 'Ubuntu', 'CentOS', 'PowerShell', 'Bash',
      'Cisco', 'Cisco IOS', 'OSPF', 'BGP', 'CCNA', 'Palo Alto', 'Fortinet',
      'Splunk', 'Microsoft Sentinel', 'QRadar',
      'Burp Suite', 'Metasploit', 'Nessus', 'Kali Linux', 'CEH',
      'Selenium', 'Cypress', 'Playwright', 'Appium',
      'Java', 'C++', 'C#', 'C', 'Kotlin', 'Swift', 'Golang', 'Rust', 'PHP',
      'Ruby',
      'Android', 'iOS', 'Flutter', 'React Native', 'SwiftUI',
      'Jetpack Compose',
      'Figma', 'Adobe XD', 'Sketch',
      'Hadoop', 'BigQuery', 'Snowflake', 'Redshift',
      'Talend', 'Informatica', 'SSIS', 'Airflow', 'Apache Airflow', 'dbt',
      'Kafka', 'Apache Kafka',
      'VMware', 'Hyper-V', 'vSphere', 'KVM', 'ESXi',
      'Active Directory', 'AD DS', 'Group Policy', 'NetApp',
      'Exchange Online', 'SharePoint', 'Microsoft Teams', 'Intune',
      'SAP FICO', 'SAP MM', 'SAP SD', 'SAP ABAP', 'ABAP', 'SAP Basis',
    ])
      normalize(name),
  };

  // ---------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------
  static const Set<String> _stopWords = {
    'and', 'of', 'the', 'for', 'in', 'with', 'to', 'a', 'an', 'on',
  };

  static Set<String> _tokens(String normalized) {
    return normalized
        .split(' ')
        .where((word) => word.isNotEmpty && !_stopWords.contains(word))
        .toSet();
  }

  /// certification skill name -> synonyms (as written in job postings).
  static const Map<String, List<String>> _groups = {
    'Databases and SQL': [
      'SQL',
      'MySQL',
      'PostgreSQL',
      'Postgres',
      'T-SQL',
      'PL/SQL',
      'SQL Server',
      'Microsoft SQL Server',
      'Oracle SQL',
      'Oracle Database',
      'SQLite',
      'Database',
      'Databases',
      'Relational Databases',
      'Relational Database',
      'RDBMS',
      'Database Management',
      'Database Administration',
      'SQL Queries',
    ],
    'Data Analysis': [
      'Data Analytics',
      'Exploratory Data Analysis',
      'EDA',
      'Analytics',
      'Data Interpretation',
      'Business Analytics',
    ],
    'Mathematics and Statistics': [
      'Statistics',
      'Statistical Analysis',
      'Probability',
      'Mathematics',
      'Math',
      'Applied Statistics',
      'Statistical Modeling',
    ],
    'Data Visualization': [
      'Data Visualisation',
      'Dashboards',
      'Dashboard',
      'Dashboarding',
      'Tableau',
      'Looker',
      'Qlik',
      'QlikView',
      'Qlik Sense',
      'Reporting',
      'Data Storytelling',
    ],
    'Power BI': [
      'Microsoft Power BI',
      'PowerBI',
    ],
    'Machine Learning': [
      'ML',
      'Machine Learning Models',
      'Supervised Learning',
      'Unsupervised Learning',
      'Scikit-learn',
      'Sklearn',
      'Predictive Modeling',
      'Predictive Analytics',
      'Model Training',
      'Feature Engineering',
      'AI',
      'Artificial Intelligence',
    ],
    'Deep Learning': [
      'Neural Networks',
      'Neural Network',
      'TensorFlow',
      'PyTorch',
      'Keras',
      'CNN',
      'Computer Vision',
      'NLP',
      'Natural Language Processing',
    ],
    'Generative AI': [
      'GenAI',
      'Gen AI',
      'Generative Artificial Intelligence',
      'Large Language Models',
      'LLM',
      'LLMs',
      'Prompt Engineering',
      'AI Agents',
      'RAG',
      'Retrieval Augmented Generation',
      'ChatGPT',
    ],
    'Python': [
      'Python Programming',
      'Python3',
      'Pandas',
      'NumPy',
      'Python Scripting',
    ],
    'JavaScript': [
      'JS',
      'Node.js',
      'NodeJS',
      'TypeScript',
      'ECMAScript',
      'ES6',
    ],
    'Frontend Frameworks': [
      'React',
      'React.js',
      'ReactJS',
      'Angular',
      'Vue',
      'Vue.js',
      'VueJS',
      'Next.js',
      'Frontend Development',
      'Front-End Development',
      'Frontend',
      'Front-End',
    ],
    'HTML and CSS': [
      'HTML',
      'CSS',
      'HTML5',
      'CSS3',
      'HTML/CSS',
      'Tailwind CSS',
      'Bootstrap',
    ],
    'Backend Development': [
      'Backend',
      'Back-End',
      'Backend Developer',
      'Server-Side Development',
      'Express',
      'Express.js',
      'Django',
      'Flask',
      'Spring Boot',
      'Laravel',
      'ASP.NET',
      '.NET',
    ],
    'APIs': [
      'API',
      'REST API',
      'REST APIs',
      'RESTful APIs',
      'RESTful API',
      'REST',
      'RESTful',
      'GraphQL',
      'API Development',
      'Web Services',
      'API Integration',
    ],
    'AWS': [
      'Amazon Web Services',
      'AWS Cloud',
      'Amazon AWS',
    ],
    'Azure': [
      'Microsoft Azure',
      'Azure Cloud',
    ],
    'Cloud Computing': [
      'Cloud',
      'Cloud Platforms',
      'Cloud Infrastructure',
      'Cloud Services',
      'GCP',
      'Google Cloud',
      'Google Cloud Platform',
      'Cloud Technologies',
      'Cloud Architecture',
    ],
    'Cloud Security': [
      'Cloud Security Posture',
      'Securing Cloud',
      'Cloud Security Architecture',
      'CSPM',
      'Cloud Data Security',
    ],
    'Containers': [
      'Docker',
      'Containerization',
      'Containerisation',
      'Podman',
      'Docker Containers',
    ],
    'Kubernetes': [
      'K8s',
      'Kube',
      'Container Orchestration',
      'Kubernetes Administration',
      'EKS',
      'AKS',
      'GKE',
    ],
    'Infrastructure as Code': [
      'IaC',
      'Terraform',
      'Ansible',
      'CloudFormation',
      'Bicep',
      'Pulumi',
      'Configuration Management',
      'Puppet',
      'Chef',
    ],
    'CI/CD': [
      'CICD',
      'Continuous Integration',
      'Continuous Delivery',
      'Continuous Deployment',
      'Jenkins',
      'GitHub Actions',
      'GitLab CI',
      'CI/CD Pipelines',
    ],
    'DevOps': [
      'DevOps Practices',
      'DevSecOps',
      'Site Reliability Engineering',
      'SRE',
      'Release Management',
    ],
    'Linux': [
      'Linux Administration',
      'Unix',
      'UNIX/Linux',
      'Red Hat',
      'RHEL',
      'Ubuntu',
      'Linux System Administration',
      'CentOS',
    ],
    'Scripting': [
      'PowerShell',
      'Bash',
      'Shell',
      'Shell Scripting',
      'Bash Scripting',
      'Automation Scripting',
    ],
    'Networking Fundamentals': [
      'Networking',
      'Computer Networking',
      'Networks',
      'Network Fundamentals',
      'Networking Basics',
      'Network Administration',
      'LAN',
      'WAN',
      'LAN/WAN',
      'Network Engineering',
    ],
    'TCP/IP': [
      'TCPIP',
      'IP Addressing',
      'Subnetting',
      'DNS',
      'DHCP',
      'OSI Model',
      'IP Networking',
      'IPv4',
      'IPv6',
    ],
    'Routing and Switching': [
      'Routing',
      'Switching',
      'Switching and Routing',
      'Cisco',
      'OSPF',
      'BGP',
      'VLAN',
      'VLANs',
      'Cisco IOS',
      'CCNA',
    ],
    'Network Security': [
      'Firewall',
      'Firewalls',
      'Network Defense',
      'IDS/IPS',
      'Intrusion Detection',
      'Intrusion Prevention',
      'VPN',
      'Palo Alto',
      'Fortinet',
      'Network Protection',
    ],
    'Wireless Networks': [
      'WiFi',
      'Wi-Fi',
      'Wireless',
      'WLAN',
      'Wireless Networking',
    ],
    'Network Automation': [
      'Network Programmability',
      'SDN',
      'Software Defined Networking',
      'NetDevOps',
    ],
    'Information Security': [
      'InfoSec',
      'Cybersecurity',
      'Cyber Security',
      'Security',
      'Security Fundamentals',
      'Information Assurance',
      'Cyber Security Fundamentals',
      'IT Security',
      'Security Controls',
      'Security Awareness',
      'Data Security',
    ],
    'Security Operations': [
      'SOC',
      'Security Information and Event Management',
      'Security Operations Center',
      'SIEM',
      'Splunk',
      'Security Monitoring',
      'SOC Analyst',
      'Log Analysis',
      'Microsoft Sentinel',
      'QRadar',
    ],
    'Incident Response': [
      'Incident Handling',
      'Incident Management',
      'IR',
      'Security Incident Response',
      'Cyber Incident Response',
    ],
    'Threat Intelligence': [
      'Cyber Threat Intelligence',
      'CTI',
      'Threat Hunting',
      'Threat Detection',
      'Threat Analysis',
      'Threat Modeling',
      'MITRE ATT&CK',
    ],
    'Penetration Testing': [
      'Pentesting',
      'Pen Testing',
      'Pentest',
      'Penetration Tester',
      'Red Team',
      'Red Teaming',
      'Vulnerability Assessment',
      'Vulnerability Management',
      'Vulnerability Scanning',
      'Burp Suite',
      'Metasploit',
      'Nessus',
    ],
    'Ethical Hacking': [
      'Hacking',
      'Ethical Hacker',
      'Offensive Security',
      'Kali Linux',
      'CEH',
    ],
    'Web Security': [
      'OWASP',
      'Application Security',
      'AppSec',
      'Secure Coding',
      'Web Application Security',
      'Secure Software Development',
    ],
    'Digital Forensics': [
      'Forensics',
      'Computer Forensics',
      'DFIR',
      'Cyber Forensics',
      'Malware Analysis',
    ],
    'Risk Management': [
      'Risk',
      'Enterprise Risk Management',
      'ERM',
      'IT Risk Management',
      'Cyber Risk Management',
    ],
    'Risk Assessment': [
      'Risk Analysis',
      'Security Risk Assessment',
      'Risk Evaluation',
    ],
    'Policies and Procedures': [
      'Policy',
      'Policies',
      'Governance',
      'GRC',
      'Governance Risk and Compliance',
      'Compliance',
      'Security Policies',
      'Security Governance',
      'Regulatory Compliance',
      'Policy Development',
    ],
    'Audit': [
      'Auditing',
      'IT Audit',
      'Security Audit',
      'Internal Audit',
      'Audit and Compliance',
      'Information Systems Audit',
    ],
    'ISO 27001': [
      'ISO27001',
      'ISO IEC 27001',
      'ISO/IEC 27001',
      'ISMS',
      'ISO 27001 2022',
      'Information Security Management System',
    ],
    'NIST CSF': [
      'NIST',
      'NIST Cybersecurity Framework',
      'NIST Framework',
    ],
    'Software Testing': [
      'Testing',
      'QA',
      'Quality Assurance',
      'Software QA',
      'Manual Testing',
      'Test Strategy',
      'Functional Testing',
      'Regression Testing',
      'Defect Tracking',
    ],
    'Test Automation': [
      'Automated Testing',
      'Selenium',
      'Cypress',
      'Playwright',
      'Test Automation Frameworks',
      'Appium',
    ],
    'Test Cases': [
      'Test Case Design',
      'Test Planning',
      'Test Design',
      'Test Scenarios',
      'Test Case Writing',
    ],
    'Programming Fundamentals': [
      'Programming',
      'Coding',
      'Software Development',
      'Java',
      'C++',
      'C#',
      'C',
      'Kotlin',
      'Swift',
      'Golang',
      'Rust',
      'PHP',
      'Ruby',
      'Programming Languages',
      'Software Engineering',
    ],
    'Object-Oriented Programming': [
      'OOP',
      'Object Oriented',
      'Object Oriented Programming',
      'Object Oriented Design',
      'OOD',
    ],
    'Data Structures and Algorithms': [
      'Algorithms',
      'Data Structures',
      'DSA',
      'Algorithm Design',
    ],
    'Mobile App Development': [
      'Android',
      'Android Development',
      'iOS',
      'iOS Development',
      'Flutter',
      'React Native',
      'Mobile Development',
      'Mobile Apps',
      'Mobile Application Development',
      'SwiftUI',
      'Jetpack Compose',
    ],
    'UI Design': [
      'UI',
      'User Interface Design',
      'Figma',
      'Adobe XD',
      'Sketch',
      'Visual Design',
      'Interface Design',
      'UI/UX Design',
    ],
    'UX Research': [
      'UX',
      'User Experience',
      'UX Design',
      'User Research',
      'Usability Testing',
      'Usability',
      'User Experience Design',
    ],
    'Prototyping': [
      'Wireframing',
      'Wireframes',
      'Prototypes',
      'Rapid Prototyping',
    ],
    'Design Thinking': [
      'Human Centered Design',
    ],
    'Accessibility': [
      'WCAG',
      'Web Accessibility',
      'A11y',
    ],
    'Big Data': [
      'Hadoop',
      'Big Data Analytics',
      'Data Lake',
      'Data Lakes',
      'Data Warehouse',
      'Data Warehousing',
      'BigQuery',
      'Snowflake',
      'Redshift',
    ],
    'Spark': [
      'Apache Spark',
      'PySpark',
      'Spark SQL',
    ],
    'ETL': [
      'ELT',
      'Data Integration',
      'Data Transformation',
      'ETL Pipelines',
      'Talend',
      'Informatica',
      'SSIS',
    ],
    'Data Pipelines': [
      'Data Pipeline',
      'Data Engineering',
      'Workflow Orchestration',
      'Airflow',
      'Apache Airflow',
      'dbt',
      'Kafka',
      'Apache Kafka',
      'Data Orchestration',
      'Streaming Data',
      'Data Streaming',
    ],
    'Performance Tuning': [
      'Query Optimization',
      'Performance Optimization',
      'Database Tuning',
      'SQL Tuning',
      'Query Tuning',
      'Performance Optimisation',
    ],
    'Database Design': [
      'Data Modeling',
      'Data Modelling',
      'Database Modeling',
      'Schema Design',
      'ERD',
      'Database Normalization',
      'Data Architecture',
    ],
    'Database Security': [
      'DB Security',
      'Database Protection',
      'Database Auditing',
    ],
    'Backup and Recovery': [
      'Backup',
      'Backups',
      'Disaster Recovery',
      'DR',
      'Business Continuity',
      'Backup and Restore',
      'Backup Recovery',
      'High Availability',
    ],
    'Virtualization': [
      'VMware',
      'Hyper-V',
      'vSphere',
      'Virtual Machines',
      'VM',
      'VMs',
      'Virtualisation',
      'KVM',
      'ESXi',
    ],
    'Servers': [
      'Server Administration',
      'Server Management',
      'Server Infrastructure',
      'Server Hardware',
    ],
    'Windows Server': [
      'Windows Server Administration',
      'Active Directory',
      'AD DS',
      'Group Policy',
      'Microsoft Server',
    ],
    'Storage': [
      'SAN',
      'NAS',
      'Storage Systems',
      'Storage Management',
      'Storage Administration',
      'NetApp',
    ],
    'Data Center Operations': [
      'Data Centre',
      'Data Center',
      'Data Centre Operations',
      'Data Center Management',
      'Datacenter',
      'Data Center Infrastructure',
    ],
    'Operating Systems': [
      'OS',
      'Operating System',
      'OS Administration',
    ],
    'Windows': [
      'Windows Administration',
      'Windows 10',
      'Windows 11',
      'Microsoft Windows',
      'Windows OS',
    ],
    'Microsoft 365': [
      'Office 365',
      'O365',
      'M365',
      'Microsoft Office',
      'MS Office',
      'Microsoft Office 365',
      'Exchange Online',
      'SharePoint',
      'Microsoft Teams',
      'Intune',
      'Microsoft 365 Administration',
    ],
    'Hardware and Software Support': [
      'IT Support',
      'Technical Support',
      'Helpdesk',
      'Help Desk',
      'Desktop Support',
      'Service Desk',
      'End User Support',
      'IT Helpdesk',
      'User Support',
    ],
    'Troubleshooting': [
      'Technical Troubleshooting',
      'Debugging',
      'Diagnostics',
      'Root Cause Analysis',
      'Fault Finding',
      'Issue Resolution',
    ],
    'Solution Architecture': [
      'Solutions Architecture',
      'Solution Design',
      'Architecture Design',
      'Systems Architecture',
      'Technical Architecture',
      'System Design',
    ],
    'Enterprise Architecture': [
      'EA',
      'Enterprise Architecture Frameworks',
      'IT Architecture',
    ],
    'TOGAF': [
      'TOGAF 9',
      'TOGAF 10',
    ],
    'SAP': [
      'SAP ERP',
      'SAP Modules',
      'SAP FICO',
      'SAP MM',
      'SAP SD',
      'SAP ABAP',
      'ABAP',
      'SAP Basis',
    ],
    'SAP S/4HANA': [
      'S4HANA',
      'SAP S4HANA',
      'S/4HANA',
    ],
    'IT Service Management': [
      'ITIL',
      'ITSM',
      'Service Management',
      'ITIL 4',
      'IT Service Delivery',
    ],
    'Service Delivery': [
      'Service Delivery Management',
    ],
    'MLOps': [
      'ML Ops',
      'Machine Learning Operations',
      'Model Deployment',
      'Model Monitoring',
      'ML Pipelines',
    ],
    'Telecom Networks': [
      'Telecommunications',
      'Telecom',
      'Telecom Network',
      'Mobile Networks',
      'Telecommunication Networks',
      'Telco',
      'RAN',
      'Radio Access Network',
    ],
    'Mobile Core (EPC / 5G)': [
      '5G',
      '5G Core',
      'LTE',
      'EPC',
      '4G',
      'Mobile Core',
      '4G LTE',
      'IMS',
      'Packet Core',
    ],
    'Fiber Optics': [
      'Fibre Optics',
      'Fiber Optic',
      'Fibre Optic',
      'FTTH',
      'Fiber',
      'Fibre',
    ],
    'Git': [
      'GitHub',
      'GitLab',
      'Version Control',
      'Source Control',
      'Git and GitHub',
    ],
  };

  static final Map<String, String> _aliases = _buildAliases();

  static Map<String, String> _buildAliases() {
    final map = <String, String>{};
    _groups.forEach((canonicalName, synonyms) {
      final target = normalize(canonicalName);
      for (final synonym in synonyms) {
        map[normalize(synonym)] = target;
      }
    });
    return map;
  }
}

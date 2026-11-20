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
    return lower.replaceAll(_nonWord, ' ').trim();
  }

  /// Built once: [normalize] runs on every title and description.
  static final RegExp _nonWord = RegExp(r'[^a-z0-9]+');

  /// The certification skill name (normalized) that [input] stands for.
  static String canonical(String input) {
    final key = normalize(input);
    return _aliases[key] ?? key;
  }

  /// True when the two skill names mean the same thing.
  static bool matches(String a, String b) =>
      matchesCanonical(canonical(a), canonical(b));

  /// [matches] for two names that already went through [canonical]. The
  /// search index uses it to normalize each skill tag once instead of on
  /// every comparison.
  static bool matchesCanonical(String ca, String cb) {
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
    return spellingsOf(key).any((v) => text.contains(' $v '));
  }

  // ---------------------------------------------------------
  // SEARCH HELPERS (used by the opportunity search index)
  // ---------------------------------------------------------

  /// The ways an already normalized name can be written in a text: itself,
  /// without spaces ("power bi" -> "powerbi"), and for names ending in js
  /// the three forms "react js", "reactjs" and "react".
  static Set<String> spellingsOf(String normalizedKey) {
    final key = normalizedKey;
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
    variants.remove('');
    return variants;
  }

  /// Rewrites the C-family language names so they survive [normalize]:
  /// "C#" -> "csharp", "C++" -> "cpp", "F#" -> "fsharp" (any case, and only
  /// as a whole name: "abc#" is left alone).
  ///
  /// [normalize] removes "#" and "+", so "C#", "C++" and "C" would all
  /// become the one letter "c". A course on C would then cover a C# gap,
  /// and the "c)" of a list ("a) ... b) ... c) ...") would count as a
  /// mention of C#. The search index runs every text and every skill
  /// through this first. [normalize] itself is left as it is, so the
  /// certifications recommender behaves as before.
  static String searchForm(String input) {
    if (!input.contains('#') && !input.contains('+')) return input;
    return input.replaceAllMapped(_cFamily, (m) {
      final name = m[0]!.toLowerCase();
      return name == 'c#' ? ' csharp ' : (name == 'f#' ? ' fsharp ' : ' cpp ');
    });
  }

  /// [normalize] after [searchForm]: the key the search index uses for a
  /// skill. "C#" -> "csharp", "SQL Server" -> "sql server".
  static String searchKey(String input) => normalize(searchForm(input));

  /// A version number may follow ("C++17" -> "cpp 17"); a letter may not.
  static final RegExp _cFamily = RegExp(
    r'(?<![a-z0-9#+])(?:c#|c\+\+|f#)(?![a-z#+])',
    caseSensitive: false,
  );

  /// True for a specific product, framework or tool (React, Tableau,
  /// Terraform ...), which only counts when it is named itself.
  static bool isSpecific(String skill) =>
      _specific.contains(normalize(skill)) ||
      _specific.contains(searchKey(skill));

  /// The separate field of study that [skill] names ("nlp" and "natural
  /// language processing" -> "natural language processing"), or null.
  /// See [_fields].
  static String? fieldOf(String skill) => _fieldOf[searchKey(skill)];

  /// The names to search for in free text when looking for [skill], without
  /// query expansion: its spellings ([spellingsOf] of its [searchKey]), and
  /// for a field of study ([fieldOf]) every name of that field, since "NLP"
  /// is only the short form of "Natural Language Processing".
  static List<String> searchNamesOf(String skill) {
    final key = searchKey(skill);
    if (key.isEmpty) return const [];
    final names = <String>{...spellingsOf(key)};
    final field = _fieldOf[key];
    if (field != null) {
      _fieldOf.forEach((name, f) {
        if (f == field) names.addAll(spellingsOf(name));
      });
    }
    return names.toList();
  }

  /// [skill] with everything the tag test needs computed once.
  static PreparedSkill prepare(String skill) {
    final key = searchKey(skill);
    return PreparedSkill._(
      key: key,
      canonical: canonical(skill),
      isSpecific:
          _specific.contains(key) || _specific.contains(normalize(skill)),
      field: _fieldOf[key],
    );
  }

  /// True when the skill tag [tag] of an opportunity stands for the skill
  /// the user [wanted]. The same rule as [matchedSkills] applies to tags: a
  /// specific product must be the tag itself, any other skill uses
  /// [matches] (so the tag "Databases and SQL" covers "SQL"). Names are
  /// compared in their [searchForm], so the tag "C" does not cover "C#".
  /// A field of study ([fieldOf]) is only covered by a tag of the same
  /// field: the tag "Deep Learning" does not cover "Computer Vision".
  static bool tagCovers(String wanted, String tag) =>
      tagCoversPrepared(prepare(wanted), prepare(tag));

  /// [tagCovers] for names that went through [prepare] (the search index
  /// prepares every tag once instead of on every comparison).
  static bool tagCoversPrepared(PreparedSkill wanted, PreparedSkill tag) {
    if (wanted.key.isEmpty) return false;
    if (wanted.isSpecific) return tag.key == wanted.key;
    if (wanted.field != null) return tag.field == wanted.field;
    return matchesCanonical(wanted.canonical, tag.canonical);
  }

  /// Query expansion: the normalized names to search for in free text
  /// (titles, objectives, descriptions) when looking for [skill].
  ///
  /// A course rarely uses the exact words of the user's skill gap. A course
  /// that teaches SQL may call it "relational databases", so searching for
  /// the gap name alone would miss it. Expansion searches for the other
  /// names of the same skill too:
  ///  - always: the skill itself and its spellings ([spellingsOf]);
  ///  - for a broad skill: the name of its synonym group ("Databases and
  ///    SQL") and the synonyms in that group.
  ///
  /// Three guards keep the search precise:
  ///  - a specific product (React, Tableau, PostgreSQL) or a field of study
  ///    ([fieldOf]) is never expanded: a course on databases does not teach
  ///    PostgreSQL;
  ///  - product names are never added as synonyms: a text that names
  ///    Tableau in passing does not teach Data Visualization as a whole;
  ///  - only synonyms of two words or more are added. One-word synonyms
  ///    ("reporting", "security", "routing", "c", "os") appear in texts
  ///    about many other subjects.
  /// Skill tags do not need these guards: they go through the full synonym
  /// table with [tagCovers].
  ///
  /// The opportunity recommender keeps expansion off by default
  /// (`expandSynonyms` in its ranking weights explains why).
  static List<String> expansionsOf(String skill) {
    final key = searchKey(skill);
    if (key.isEmpty) return const [];
    final names = <String>{...searchNamesOf(skill)};
    // A field of study is not widened to its group either: a text on
    // neural networks does not teach Computer Vision.
    if (!isSpecific(skill) && fieldOf(skill) == null) {
      final group = canonical(key);
      names.add(group);
      for (final synonym in _synonymsOf[group] ?? const <String>[]) {
        if (synonym.length > 2 &&
            synonym.contains(' ') &&
            !_specific.contains(synonym)) {
          names.add(synonym);
        }
      }
    }
    return names.toList();
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
      // Both forms: "c" for the certifications, "csharp" and "cpp" for the
      // opportunity search ([searchKey]).
      ...{normalize(name), searchKey(name)},
  };

  /// Separate fields of study inside one synonym group, with their other
  /// names. For certifications, NLP and Computer Vision both count as Deep
  /// Learning (the certification skill name), and [canonical] and
  /// [matches] keep that. But a course on one does not teach the other, so
  /// the opportunity search keeps them apart ([fieldOf], [tagCovers]). An
  /// abbreviation is listed here because it is another spelling of the
  /// same field, not a synonym. ("CV" is left out: it also means a resume.)
  static const Map<String, List<String>> _fields = {
    'Natural Language Processing': ['NLP'],
    'Computer Vision': [],
  };

  /// normalized name -> normalized field name (from [_fields]).
  static final Map<String, String> _fieldOf = {
    for (final entry in _fields.entries) ...{
      normalize(entry.key): normalize(entry.key),
      for (final name in entry.value) normalize(name): normalize(entry.key),
    },
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

  /// normalized certification skill name -> its normalized synonyms.
  static final Map<String, List<String>> _synonymsOf = {
    for (final entry in _groups.entries)
      normalize(entry.key): [for (final s in entry.value) normalize(s)],
  };

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

/// A skill name with the values [SkillMatcher.tagCoversPrepared] needs,
/// computed once ([SkillMatcher.prepare]).
class PreparedSkill {
  /// [SkillMatcher.searchKey] of the name.
  final String key;

  /// [SkillMatcher.canonical] of the name.
  final String canonical;

  /// [SkillMatcher.isSpecific] of the name.
  final bool isSpecific;

  /// [SkillMatcher.fieldOf] of the name.
  final String? field;

  const PreparedSkill._({
    required this.key,
    required this.canonical,
    required this.isSpecific,
    required this.field,
  });
}

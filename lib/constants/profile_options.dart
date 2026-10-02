// All dropdown options in one place (matches the Profile Setup code).
// Save the value exactly as written here.
// Career Goal saves the key (ID), not the label.

class ProfileOptions {
  // 29 public + 15 private universities + Other
  static const List<String> universities = [
    'King Saud University',
    'King Abdulaziz University',
    'King Fahd University of Petroleum and Minerals',
    'Imam Mohammad Ibn Saud Islamic University',
    'Umm Al-Qura University',
    'Islamic University of Madinah',
    'King Faisal University',
    'King Khalid University',
    'Qassim University',
    'Taibah University',
    'Taif University',
    'University of Hail',
    'Jazan University',
    'Jouf University',
    'Al-Baha University',
    'University of Tabuk',
    'Najran University',
    'Northern Border University',
    'Princess Nourah bint Abdulrahman University',
    'King Saud bin Abdulaziz University for Health Sciences',
    'Imam Abdulrahman Bin Faisal University',
    'Prince Sattam bin Abdulaziz University',
    'Shaqra University',
    'Majmaah University',
    'Saudi Electronic University',
    'University of Jeddah',
    'University of Bisha',
    'University of Hafr Al Batin',
    'King Abdullah University of Science and Technology (KAUST)',
    'Alfaisal University',
    'Prince Sultan University',
    'Effat University',
    'Dar Al-Hekma University',
    'Prince Mohammad bin Fahd University',
    'Al Yamamah University',
    'Dar Al Uloom University',
    'Riyadh Elm University',
    'AlMaarefa University',
    'University of Business and Technology',
    'Arab Open University',
    'Prince Mugrin University',
    'Fahad Bin Sultan University',
    'Mustaqbal University',
    'Sulaiman Al Rajhi University',
    'Other',
  ];

  static const List<String> degrees = [
    'Diploma',
    'Bachelor',
    'Master',
    'PhD',
  ];

  static const List<String> majors = [
    'Computer Science',
    'Information Technology',
    'Information Systems',
    'Software Engineering',
    'Computer Engineering',
    'Network Engineering',
    'Cybersecurity',
    'Information Security',
    'Artificial Intelligence',
    'Data Science',
    'Internet of Things',
  ];

  static const List<String> graduationStatuses = [
    'Student',
    'Fresh Graduate',
    'Graduate',
  ];

  // Shown as text in the dropdown, saved as int with int.parse()
  static final List<String> graduationYears = [
    for (int year = 2026; year >= 2016; year--) year.toString(),
  ];

  static const List<String> experienceLevels = [
    'No Experience',
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  // key = careerGoalId (saved), value = label (shown).
  // Same IDs as the careerPaths collection.
  static const Map<String, String> careerGoals = {
    'software_engineer': 'Software Engineer',
    'web_developer': 'Web Developer',
    'mobile_developer': 'Mobile Developer',
    'data_analyst': 'Data Analyst',
    'data_scientist': 'Data Scientist',
    'ai_ml_engineer': 'AI / Machine Learning Engineer',
    'cybersecurity_analyst': 'Cybersecurity Analyst',
    'cloud_devops_engineer': 'Cloud / DevOps Engineer',
    'network_engineer': 'Network Engineer',
    'systems_administrator': 'Systems Administrator',
    'database_administrator': 'Database Administrator',
    'ui_ux_designer': 'UI/UX Designer',
    'business_analyst': 'Business Analyst',
    'it_project_manager': 'IT Project Manager',
    'it_consultant': 'IT Consultant',
  };

  static const List<String> communityTopics = [
    'Career Advice',
    'Interview Experience',
    'CV and Portfolio',
    'Certifications',
    'Courses and Learning',
    'Internships and Co-op',
    'Job Opportunities',
    'Projects',
    'Hackathons and Events',
    'General',
  ];

  static const int maxPostLength = 1000;
}

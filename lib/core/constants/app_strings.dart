import 'package:flutter/material.dart';

class AppStrings {
  AppStrings._();

  static String tr(BuildContext context, {required String ar, required String en}) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return isArabic ? ar : en;
  }

  // General
  static String appName(BuildContext context) =>
      tr(context, ar: 'على الطريق', en: 'On the Road');
  static String currency(BuildContext context) =>
      tr(context, ar: 'ج.م', en: 'EGP');

  // Screen 1: Welcome Screen (Figma exact match)
  static String welcomeHeaderSub(BuildContext context) =>
      tr(context, ar: 'رحلتك أسهل معانا', en: 'Your journey is easier with us');
  static String heroTagline(BuildContext context) =>
      tr(context, ar: 'كل رحلة،\nتبدأ من هنا.', en: 'Every journey,\nstarts here.');
  static String heroSubtitle(BuildContext context) =>
      tr(context, ar: 'اختار رحلتك واستمتع بالطريق.', en: 'Choose your ride and enjoy the road.');
  static String getStarted(BuildContext context) =>
      tr(context, ar: 'ابدأ الآن', en: 'Get started');
  static String alreadyHaveAccount(BuildContext context) =>
      tr(context, ar: 'لديك حساب بالفعل؟', en: 'Already have an account?');
  static String loginButton(BuildContext context) =>
      tr(context, ar: 'سجل الدخول', en: 'Log in');

  // Screen 2: Login
  static String welcomeBack(BuildContext context) =>
      tr(context, ar: 'أهلاً بك مجدداً', en: 'Welcome back');
  static String loginSubtitle(BuildContext context) =>
      tr(context, ar: 'سجل الدخول لمتابعة رحلاتك وحجوزاتك', en: 'Sign in to manage your rides and bookings');
  static String phoneNumber(BuildContext context) =>
      tr(context, ar: 'رقم الهاتف', en: 'Phone number');
  static String phoneHint(BuildContext context) =>
      tr(context, ar: '01XXXXXXXXX', en: '01XXXXXXXXX');
  static String dontHaveAccount(BuildContext context) =>
      tr(context, ar: 'ليس لديك حساب؟', en: "Don't have an account?");
  static String createAccount(BuildContext context) =>
      tr(context, ar: 'إنشاء حساب جديد', en: 'Create account');

  // Screen 3: Register
  static String createYourAccount(BuildContext context) =>
      tr(context, ar: 'إنشاء حسابك', en: 'Create your account');
  static String selectRoleSubtitle(BuildContext context) =>
      tr(context, ar: 'اختر نوع الحساب للبدء', en: 'Choose your account type to begin');
  static String passenger(BuildContext context) =>
      tr(context, ar: 'راكب', en: 'Passenger');
  static String driver(BuildContext context) =>
      tr(context, ar: 'سائق', en: 'Driver');
  static String fullName(BuildContext context) =>
      tr(context, ar: 'الاسم بالكامل', en: 'Full name');
  static String continueBtn(BuildContext context) =>
      tr(context, ar: 'متابعة', en: 'Continue');

  // Screen 4: Personal Details
  static String personalDetails(BuildContext context) =>
      tr(context, ar: 'البيانات الشخصية', en: 'Personal details');
  static String personalDetailsSub(BuildContext context) =>
      tr(context, ar: 'أدخل بياناتك الرسمية لإكمال توثيق الحساب', en: 'Enter your official information to complete verification');
  static String nationalId(BuildContext context) =>
      tr(context, ar: 'الرقم القومي (14 رقم)', en: 'National ID (14 digits)');
  static String dateOfBirth(BuildContext context) =>
      tr(context, ar: 'تاريخ الميلاد', en: 'Date of birth');
  static String gender(BuildContext context) =>
      tr(context, ar: 'النوع', en: 'Gender');
  static String male(BuildContext context) =>
      tr(context, ar: 'ذكر', en: 'Male');
  static String female(BuildContext context) =>
      tr(context, ar: 'أنثى', en: 'Female');
  static String city(BuildContext context) =>
      tr(context, ar: 'المحافظة / المدينة', en: 'Governorate / City');
  static String saveAndContinue(BuildContext context) =>
      tr(context, ar: 'حفظ ومتابعة', en: 'Save & continue');

  // Screen 5: Identity Verification / Selfie
  static String verifyIdentity(BuildContext context) =>
      tr(context, ar: 'التحقق من هويتك', en: 'Verify your identity');
  static String selfieInstruction(BuildContext context) =>
      tr(context, ar: 'ضع وجهك داخل الإطار لالتقاط صورة التحقق المباشرة', en: 'Position your face inside the frame for verification');
  static String takePhoto(BuildContext context) =>
      tr(context, ar: 'التقاط الصورة', en: 'Take photo');
  static String retake(BuildContext context) =>
      tr(context, ar: 'إعادة الالتقاط', en: 'Retake');

  // Screen 6: Driver Documents Upload
  static String driverDocs(BuildContext context) =>
      tr(context, ar: 'وثائق السائق', en: 'Driver documents');
  static String driverDocsSub(BuildContext context) =>
      tr(context, ar: 'ارفع صور واضحة لبطاقة الرقم القومي ورخصة القيادة', en: 'Upload clear photos of your National ID and driving license');
  static String idFront(BuildContext context) =>
      tr(context, ar: 'بطاقة الرقم القومي (الوجه الأمامي)', en: 'National ID (Front)');
  static String idBack(BuildContext context) =>
      tr(context, ar: 'بطاقة الرقم القومي (الوجه الخلفي)', en: 'National ID (Back)');
  static String drivingLicense(BuildContext context) =>
      tr(context, ar: 'رخصة القيادة السارية', en: 'Valid Driving License');
  static String tapToUpload(BuildContext context) =>
      tr(context, ar: 'اضغط للرفع أو التقاط صورة', en: 'Tap to upload or take a photo');
  static String submitDocs(BuildContext context) =>
      tr(context, ar: 'إرسال المستندات', en: 'Submit documents');

  // Screen 7: Verification Submitted Success
  static String docsSubmitted(BuildContext context) =>
      tr(context, ar: 'تم إرسال المستندات بنجاح', en: 'Documents submitted successfully');
  static String underReview(BuildContext context) =>
      tr(context, ar: 'طلبك قيد المراجعة حالياً من فريق الإدارة لضمان أمان الرحلات. سنرسل لك إشعاراً فور الاعتماد.', en: 'Your application is currently under review by our admin team. We will notify you once approved.');
  static String pendingStatus(BuildContext context) =>
      tr(context, ar: 'قيد المراجعة', en: 'Pending review');
  static String goToHome(BuildContext context) =>
      tr(context, ar: 'الانتقال إلى الرئيسية', en: 'Go to Home');

  // Screen 8: OTP
  static String enterOtp(BuildContext context) =>
      tr(context, ar: 'أدخل رمز التحقق', en: 'Enter your code');
  static String otpSentTo(BuildContext context, String phone) =>
      tr(context, ar: 'أرسلنا رمزاً مكوناً من 6 أرقام إلى $phone', en: 'We sent a 6-digit code to $phone');
  static String verifyBtn(BuildContext context) =>
      tr(context, ar: 'تأكيد', en: 'Verify');
  static String resendCode(BuildContext context) =>
      tr(context, ar: 'إعادة إرسال الرمز', en: 'Resend code');

  // Screen 9: Profile
  static String profile(BuildContext context) =>
      tr(context, ar: 'الملف الشخصي', en: 'Profile');
  static String verifiedUser(BuildContext context) =>
      tr(context, ar: 'حساب موثق رسمياً', en: 'Officially verified');
  static String vehicleInfo(BuildContext context) =>
      tr(context, ar: 'بيانات السيارة ورخصة القيادة', en: 'Vehicle & License Info');
  static String language(BuildContext context) =>
      tr(context, ar: 'لغة التطبيق', en: 'Language');
  static String darkMode(BuildContext context) =>
      tr(context, ar: 'الوضع الداكن', en: 'Dark mode');
  static String helpSupport(BuildContext context) =>
      tr(context, ar: 'المساعدة والدعم', en: 'Help & Support');
  static String logout(BuildContext context) =>
      tr(context, ar: 'تسجيل الخروج', en: 'Log out');

  // Screen 10 & 12: Search Trips
  static String findRide(BuildContext context) =>
      tr(context, ar: 'البحث عن رحلة', en: 'Find a ride');
  static String findRideSub(BuildContext context) =>
      tr(context, ar: 'حدد نقطة الانطلاق والوجهة والتاريخ', en: 'Select pickup, destination and date');
  static String fromCity(BuildContext context) =>
      tr(context, ar: 'مدينة الانطلاق (من)', en: 'Leaving from');
  static String toCity(BuildContext context) =>
      tr(context, ar: 'الوجهة (إلى)', en: 'Going to');
  static String date(BuildContext context) =>
      tr(context, ar: 'تاريخ الرحلة', en: 'Date');
  static String seatsCount(BuildContext context) =>
      tr(context, ar: 'عدد المقاعد', en: 'Seats needed');
  static String searchRidesBtn(BuildContext context) =>
      tr(context, ar: 'بحث عن رحلات', en: 'Search rides');

  // Screen 11: Ride Results
  static String availableRides(BuildContext context) =>
      tr(context, ar: 'الرحلات المتاحة', en: 'Available rides');
  static String availableSeats(BuildContext context, int count) =>
      tr(context, ar: '$count مقاعد متبقية', en: '$count seats left');
  static String perSeat(BuildContext context) =>
      tr(context, ar: 'لكل مقعد', en: 'per seat');

  // Screen 12: Trip Details
  static String tripDetails(BuildContext context) =>
      tr(context, ar: 'تفاصيل الرحلة', en: 'Trip details');
  static String routeStations(BuildContext context) =>
      tr(context, ar: 'مسار المحطات والتوقفات', en: 'Route stops & stations');
  static String driverInfo(BuildContext context) =>
      tr(context, ar: 'بيانات السائق', en: 'Driver info');
  static String carDetails(BuildContext context) =>
      tr(context, ar: 'مواصفات السيارة', en: 'Car specifications');
  static String bookNow(BuildContext context) =>
      tr(context, ar: 'احجز مقعدك الآن', en: 'Book your seat now');

  // Screen 13: Confirm Booking / Seat Selection
  static String confirmBooking(BuildContext context) =>
      tr(context, ar: 'تأكيد الحجز', en: 'Confirm booking');
  static String selectSeats(BuildContext context) =>
      tr(context, ar: 'اختر المقاعد المطلوبة', en: 'Select your seats');
  static String totalAmount(BuildContext context) =>
      tr(context, ar: 'المبلغ الإجمالي', en: 'Total amount');
  static String confirmRequestBtn(BuildContext context) =>
      tr(context, ar: 'تأكيد وإرسال طلب الحجز', en: 'Confirm & send booking request');
  static String proceedToPayment(BuildContext context) =>
      tr(context, ar: 'المتابعة إلى الدفع', en: 'Proceed to payment');

  // ==========================================================
  // Screen 14: Payment / الدفع (matching Figma ar-payment & en-payment)
  // ==========================================================
  static String payment(BuildContext context) =>
      tr(context, ar: 'الدفع', en: 'Payment');
  static String paymentMethod(BuildContext context) =>
      tr(context, ar: 'طريقة الدفع', en: 'Payment method');
  static String cashToDriver(BuildContext context) =>
      tr(context, ar: 'كاش للسائق', en: 'Cash to driver');
  static String payWhenYouBoard(BuildContext context) =>
      tr(context, ar: 'ادفع عند الركوب', en: 'Pay when you board');
  static String vodafoneCash(BuildContext context) =>
      tr(context, ar: 'فودافون كاش', en: 'Vodafone Cash');
  static String bankCard(BuildContext context) =>
      tr(context, ar: 'كارت بنكي', en: 'Bank card');
  static String seatCalc(BuildContext context, int count, int price) =>
      tr(context, ar: '$count مقعد × $price', en: '$count seat × $price');
  static String serviceFee(BuildContext context) =>
      tr(context, ar: 'رسوم الخدمة', en: 'Service fee');
  static String total(BuildContext context) =>
      tr(context, ar: 'الإجمالي', en: 'Total');
  static String noHiddenFees(BuildContext context) =>
      tr(context, ar: 'لا رسوم خفية', en: 'No hidden fees');
  static String confirmAndSendRequest(BuildContext context) =>
      tr(context, ar: 'تأكيد وإرسال الطلب', en: 'Confirm and send request');

  // ==========================================================
  // Screen 15: Booking Confirmation / تم إرسال طلبك
  // (matching Figma ar-booking-confirm... & en-booking-confirm...)
  // ==========================================================
  static String requestSent(BuildContext context) =>
      tr(context, ar: 'تم إرسال طلبك', en: 'Request sent');
  static String bookingRequestSent(BuildContext context) =>
      tr(context, ar: 'تم إرسال طلب الحجز', en: 'Booking request sent');
  static String weWillNotifyDriver(BuildContext context) =>
      tr(context, ar: 'هنبلغك أول ما السائق يرد على طلبك', en: "We'll notify you as soon as the driver responds");
  static String waitingForDriver(BuildContext context) =>
      tr(context, ar: 'في انتظار السائق', en: 'Waiting for driver');
  static String ramsesStation(BuildContext context) =>
      tr(context, ar: 'محطة رمسيس', en: 'Ramses Station');
  static String sidiGaberStation(BuildContext context) =>
      tr(context, ar: 'محطة سيدي جابر', en: 'Sidi Gaber Station');
  static String yourDriverForTrip(BuildContext context) =>
      tr(context, ar: 'سائقك لهذه الرحلة', en: 'Your driver for this trip');
  static String seatCountLabel(BuildContext context, int count) =>
      tr(context, ar: '$count مقعد', en: '$count seat');
  static String bookingRef(BuildContext context, String code) =>
      tr(context, ar: 'رقم الحجز: $code', en: 'Booking ref: $code');
  static String viewMyTrips(BuildContext context) =>
      tr(context, ar: 'عرض رحلاتي', en: 'View my trips');
  static String backToHome(BuildContext context) =>
      tr(context, ar: 'الرجوع للرئيسية', en: 'Back to home');

  // Navigation Items
  static String navHome(BuildContext context) =>
      tr(context, ar: 'الرئيسية', en: 'Home');
  static String navRides(BuildContext context) =>
      tr(context, ar: 'رحلاتي', en: 'Rides');
  static String navMessages(BuildContext context) =>
      tr(context, ar: 'الرسائل', en: 'Messages');
  static String navAccount(BuildContext context) =>
      tr(context, ar: 'حسابي', en: 'Account');

  // Booking Summary helpers
  static String bookingSuccess(BuildContext context) =>
      tr(context, ar: 'تم إرسال طلب الحجز بنجاح!', en: 'Booking request sent successfully!');
  static String bookingSuccessSub(BuildContext context) =>
      tr(context, ar: 'تم إخطار السائق بطلبك وستتلقى إشعاراً فور قبوله.', en: 'The driver has been notified and you will receive an update once confirmed.');
  static String bookingCode(BuildContext context) =>
      tr(context, ar: 'رمز الحجز', en: 'Booking Reference');

  // Screen: My Trips
  static String myTrips(BuildContext context) =>
      tr(context, ar: 'رحلاتي وحجوزاتي', en: 'My rides & bookings');
  static String upcoming(BuildContext context) =>
      tr(context, ar: 'القادمة', en: 'Upcoming');
  static String past(BuildContext context) =>
      tr(context, ar: 'السابقة', en: 'Past');
  static String confirmedStatus(BuildContext context) =>
      tr(context, ar: 'مؤكد', en: 'Confirmed');
  static String completedStatus(BuildContext context) =>
      tr(context, ar: 'مكتملة', en: 'Completed');
}

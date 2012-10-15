package com.ccvb.utils.crashreporter;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManager.NameNotFoundException;

public class Constants
{
	public static String SENDER_VERSION = "1";
	public static String CONTACT = "";
	public static String USER_ID = "1";
	
	// Since the exception handler doesn't have access to the context,
	// or anything really, the library prepares these values for when
	// the handler needs them.
	public static String FILES_PATH = null;
	public static String APP_VERSION = null;
	public static String APP_PACKAGE = null;
	public static String APP_NAME = null;
	
	public static String ANDROID_VERSION = null;
	public static String PHONE_MODEL = null;
	public static String PHONE_MANUFACTURER = null;
	
	public static void loadFromContext(Context context)
	{
		Constants.ANDROID_VERSION = android.os.Build.VERSION.RELEASE;
		Constants.PHONE_MODEL = android.os.Build.MODEL;
		Constants.PHONE_MANUFACTURER = android.os.Build.MANUFACTURER;
		
		PackageManager packageManager = context.getPackageManager();
		try
		{
			PackageInfo packageInfo = packageManager.getPackageInfo(context.getPackageName(), 0);
			Constants.APP_VERSION = "" + packageInfo.versionCode;
			Constants.APP_PACKAGE = packageInfo.packageName;
			Constants.APP_NAME = (String) packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageInfo.packageName, 0));
			Constants.FILES_PATH = context.getFilesDir().getAbsolutePath();
		}
		catch (NameNotFoundException e)
		{
			e.printStackTrace();
		}
	}
}
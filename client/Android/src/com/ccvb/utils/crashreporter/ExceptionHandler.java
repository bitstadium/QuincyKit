package com.ccvb.utils.crashreporter;

import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.io.Writer;
import java.lang.Thread.UncaughtExceptionHandler;
import java.util.Date;
import java.util.UUID;

import android.util.Log;

public class ExceptionHandler implements UncaughtExceptionHandler
{
	private static final String TAG = "ExceptionHandler";
	
	private UncaughtExceptionHandler defaultExceptionHandler;
	
	public ExceptionHandler(UncaughtExceptionHandler defaultExceptionHandler)
	{
		this.defaultExceptionHandler = defaultExceptionHandler;
	}
	
	@Override
	public void uncaughtException(Thread thread, Throwable exception)
	{
		final Date now = new Date();
		final Writer result = new StringWriter();
		final PrintWriter printWriter = new PrintWriter(result);
		
		exception.printStackTrace(printWriter);
		Throwable cause = exception.getCause();
		printWriter.append("\n____");
		exception.printStackTrace(printWriter);
		printWriter.append("\n\n");
		printWriter.append(cause != null ? cause.toString() : "Cause is null");
		
		try
		{
			// Create filename from a random uuid
			String filename = UUID.randomUUID().toString();
			String path = Constants.FILES_PATH + "/" + filename + ".stacktrace";
			Log.d(ExceptionHandler.TAG, "Writing unhandled exception to: " + path);
			
			// Write the stacktrace to disk
			BufferedWriter write = new BufferedWriter(new FileWriter(path));
			write.write("Package: " + Constants.APP_PACKAGE + "\n");
			write.write("Version: " + Constants.APP_VERSION + "\n");
			write.write("Android: " + Constants.ANDROID_VERSION + "\n");
			write.write("Manufacturer: " + Constants.PHONE_MANUFACTURER + "\n");
			write.write("Model: " + Constants.PHONE_MODEL + "\n");
			write.write("Date: " + now + "\n");
			write.write("\n");
			write.write(result.toString());
			write.flush();
			write.close();
		}
		catch (Exception another)
		{
			Log.e(ExceptionHandler.TAG, "Error saving exception stacktrace!");
			another.printStackTrace();
		}
		
		this.defaultExceptionHandler.uncaughtException(thread, exception);
	}
}
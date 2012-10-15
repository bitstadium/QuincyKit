package com.ccvb.utils.crashreporter;

import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FilenameFilter;
import java.io.InputStreamReader;
import java.lang.Thread.UncaughtExceptionHandler;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLConnection;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

import android.content.Context;
import android.util.Log;

public class CrashManager
{
	private static String TAG = "CrashManager";
	
	private static String identifier = null;
	private static String urlString = null;
	
	public static void register(final Context context, String urlString, String appIdentifier)
	{
		CrashManager.urlString = urlString;
		CrashManager.identifier = appIdentifier;
		
		Constants.loadFromContext(context);
		
		if (CrashManager.identifier == null)
		{
			CrashManager.identifier = Constants.APP_PACKAGE;
		}
		
		if (CrashManager.hasStackTraces())
		{
			new Thread(new Runnable()
			{
				@Override
				public void run()
				{
					CrashManager.submitStackTraces(context);
				}
			}).start();
		}
		CrashManager.registerHandler();
	}
	
	public static void register(Context context, String url)
	{
		CrashManager.register(context, url, null);
	}
	
	private static void registerHandler()
	{
		// Get current handler
		UncaughtExceptionHandler currentHandler = Thread.getDefaultUncaughtExceptionHandler();
		if (currentHandler != null)
		{
			Log.d(CrashManager.TAG, "Current handler class = " + currentHandler.getClass().getName());
		}
		
		// Register if not already registered
		if (!(currentHandler instanceof ExceptionHandler))
		{
			Thread.setDefaultUncaughtExceptionHandler(new ExceptionHandler(currentHandler));
		}
	}
	
	public static void deleteStackTraces(Context context)
	{
		Log.d(CrashManager.TAG, "Looking for exceptions in: " + Constants.FILES_PATH);
		String[] list = CrashManager.searchForStackTraces();
		
		if ((list != null) && (list.length > 0))
		{
			Log.d(CrashManager.TAG, "Found " + list.length + " stacktrace(s).");
			
			for (int index = 0; index < list.length; index++)
			{
				try
				{
					Log.d(CrashManager.TAG, "Delete stacktrace " + list[index] + ".");
					context.deleteFile(list[index]);
				}
				catch (Exception e)
				{
					e.printStackTrace();
				}
			}
		}
	}
	
	public static void submitStackTraces(Context context)
	{
		Log.d(CrashManager.TAG, "Looking for exceptions in: " + Constants.FILES_PATH);
		String[] list = CrashManager.searchForStackTraces();
		
		if ((list != null) && (list.length > 0))
		{
			Log.d(CrashManager.TAG, "Found " + list.length + " stacktrace(s).");
			
			for (int index = 0; index < list.length; index++)
			{
				try
				{
					// Read contents of stack trace
					StringBuilder contents = new StringBuilder();
					BufferedReader reader = new BufferedReader(new InputStreamReader(context.openFileInput(list[index])));
					String line = null;
					while ((line = reader.readLine()) != null)
					{
						contents.append(line);
						contents.append(System.getProperty("line.separator"));
					}
					reader.close();
					
					String[] fileContent = contents.toString().split("____");
					String stacktrace = fileContent[0];
					String cause = fileContent[1];
					
					String xmlCrash = "<crash><applicationname>"+Constants.APP_NAME+"</applicationname><bundleidentifier>"+Constants.APP_PACKAGE+"</bundleidentifier><systemversion>"+Constants.ANDROID_VERSION+"</systemversion><platform>"+Constants.PHONE_MANUFACTURER+" "+Constants.PHONE_MODEL+"</platform><senderversion>"+Constants.SENDER_VERSION+"</senderversion><version>"+Constants.APP_VERSION+"</version><log><![CDATA["+stacktrace+"]]></log><userid>"+Constants.USER_ID+"</userid><contact>"+Constants.CONTACT+"</contact><description><![CDATA["+cause+"]]></description></crash>";
					
					String boundary = "----FOO";
					URL url = new URL(CrashManager.urlString);
					URLConnection urlConnection;
					if ("https".equals(url.getProtocol()))
					{
						CrashManager.trustAllHosts();
						HttpsURLConnection tempUrlConnection = (HttpsURLConnection) url.openConnection();
						tempUrlConnection.setHostnameVerifier(CrashManager.HOSTNAME_VERIFIER);
						urlConnection = tempUrlConnection;
					}
					else
					{
						urlConnection = url.openConnection();
					}
					urlConnection.setUseCaches(false);  
					urlConnection.setDoInput(true);  
					urlConnection.setDoOutput(true);  
//					urlConnection.addRequestProperty("Accept-Encoding", "gzip");
					urlConnection.addRequestProperty("User-Agent", "Quincy/Android");
					urlConnection.setConnectTimeout(15 * 1000);
					urlConnection.addRequestProperty("Method", "POST");
					urlConnection.addRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
					
					StringBuffer postBody = new StringBuffer();
					postBody.append("--" + boundary + "\r\n");
					postBody.append("Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n");
					postBody.append("<crashes>"+xmlCrash+"</crashes>");
					postBody.append("\r\n--" + boundary + "--\r\n");
					
					DataOutputStream out = new DataOutputStream(urlConnection.getOutputStream());  
		            out.write(postBody.toString().getBytes("UTF-8"));  
		            out.flush();  
		            out.close();  
					
					urlConnection.connect();
					Log.v(CrashManager.TAG, "Connected");
					BufferedReader in = null;  
	                in = new BufferedReader(new InputStreamReader(urlConnection.getInputStream()));
	                
	                StringBuilder responseBuilder = new StringBuilder();
	                String responseLine = "";
	                while ((responseLine = in.readLine()) != null)
	                {
	                    responseBuilder.append(responseLine);
	                }
	                String responseData = responseBuilder.toString();
	                
	                int httpResponseCode = ((HttpURLConnection)urlConnection).getResponseCode();
	                if (httpResponseCode >= 200 && httpResponseCode < 400 && responseData != null && responseData.length() > 0)
	                {
	                	try
	                	{
	                		context.deleteFile(list[index]);
	                		Log.v(CrashManager.TAG, "Crash file deleted");
	                	}
	                	catch (Exception e)
	                	{
	                		e.printStackTrace();
	                		Log.v(CrashManager.TAG, "Error while deleting crash file");
	                	}
	                }
	                else
	                {
	                	Log.v(CrashManager.TAG, "Error while sending crash file : HTTP STATUS CODE ["+httpResponseCode+"] with response ["+responseData+"]");
	                	Log.v(CrashManager.TAG, "Response : " + responseData);
	                }
	                
				}
				catch (Exception e)
				{
					e.printStackTrace();
				}
			}
		}
	}
	
	public static boolean hasStackTraces()
	{
		return CrashManager.searchForStackTraces().length > 0;
	}
	
	private static String[] searchForStackTraces()
	{
		// Try to create the files folder if it doesn't exist
		File dir = new File(Constants.FILES_PATH + "/");
		dir.mkdir();
		
		// Filter for ".stacktrace" files
		FilenameFilter filter = new FilenameFilter()
		{
			public boolean accept(File dir, String name)
			{
				return name.endsWith(".stacktrace");
			}
		};
		return dir.list(filter);
	}
	
	// always verify the host - dont check for certificate
	private final static HostnameVerifier HOSTNAME_VERIFIER = new HostnameVerifier()
	{
		public boolean verify(String hostname, SSLSession session)
		{
			Log.d(CrashManager.TAG, "Verifying hostname : " + hostname);
			return CrashManager.urlString.contains(hostname);
		}
	};
	
	/**
	 * Trust every server - dont check for any certificate
	 */
	private static void trustAllHosts()
	{
		// Create a trust manager that does not validate certificate chains
		TrustManager[] trustAllCerts = new TrustManager[] { new X509TrustManager()
		{
			public java.security.cert.X509Certificate[] getAcceptedIssuers()
			{
				return new java.security.cert.X509Certificate[] {};
			}
			
			public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException
			{
			}
			
			public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException
			{
			}
		} };
		
		// Install the all-trusting trust manager
		try
		{
			SSLContext sc = SSLContext.getInstance("TLS");
			sc.init(null, trustAllCerts, new java.security.SecureRandom());
			HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());
		}
		catch (Exception e)
		{
			e.printStackTrace();
		}
	}
}
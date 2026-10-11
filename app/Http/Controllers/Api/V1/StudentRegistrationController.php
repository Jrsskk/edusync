<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Notifications\StudentEmailVerificationNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules;

class StudentRegistrationController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $request->merge([
            'name' => is_string($request->input('name')) ? trim($request->input('name')) : $request->input('name'),
            'email' => is_string($request->input('email')) ? Str::lower(trim($request->input('email'))) : $request->input('email'),
        ]);

        $validated = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:255', 'regex:/^\S+\s+\S/'],
            'email' => ['required', 'string', 'lowercase', 'email', 'max:255', 'unique:'.User::class],
            'password' => ['required', 'confirmed', Rules\Password::min(8)->mixedCase()->numbers()->symbols()],
        ]);

        $nameParts = preg_split('/\s+/', trim($validated['name']));
        $firstName = array_shift($nameParts);
        $lastName = array_pop($nameParts);
        $user = User::create([
            'first_name' => $firstName,
            'middle_name' => $nameParts ? implode(' ', $nameParts) : null,
            'last_name' => $lastName,
            'username' => 'student-'.Str::uuid(),
            'email' => $validated['email'],
            'password' => $validated['password'],
            'role' => UserRole::Student,
        ]);

        $user->notify(new StudentEmailVerificationNotification);

        return response()->json([
            'success' => true,
            'message' => 'Account created. Check your email for a verification link.',
            'data' => ['email' => $user->email],
        ], 201);
    }

    public function resendVerification(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email'],
        ]);
        $user = User::where('email', Str::lower(trim($validated['email'])))->first();

        if ($user?->isStudent() && $user->email_verified_at === null) {
            $user->notify(new StudentEmailVerificationNotification);
        }

        return response()->json([
            'success' => true,
            'message' => 'If the Student account exists and is unverified, a verification link has been sent.',
        ]);
    }

    public function verify(Request $request, string $id, string $hash): JsonResponse
    {
        $user = User::findOrFail($id);
        abort_unless($user->isStudent() && hash_equals(sha1($user->email), $hash), 403);

        if ($user->email_verified_at === null) {
            $user->forceFill(['email_verified_at' => now()])->save();
        }

        return response()->json([
            'success' => true,
            'message' => 'Email verified successfully. You can now sign in to EduSync Student.',
        ]);
    }
}

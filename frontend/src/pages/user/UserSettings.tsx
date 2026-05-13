'use client';

import { useState, useRef } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Upload, X, Loader2, Save } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import UserLayout from './UserLayout';
import { GetRequestAxios, PatchRequestAxios, PostRequestAxios } from '../../../api-hooks/api-hooks';
import { useQueryWrapper } from '../../../api-hooks/react-query-wrapper';

type UserProfile = {
  _id: string;
  name: string;
  email?: string;
  phone?: string;
  whatsapp?: string;
  gender?: string;
  maritalStatus?: string;
  age?: number;
  bloodGroup?: string;
  weight?: number;
  profileImage?: { url?: string; key?: string };
  role: string;
  isActive: boolean;
  isPublished: boolean;
  credits?: number;
};

type ImageUploadResponse = {
  data: { url: string; key: string };
};

type UserFormData = {
  name: string;
  phone: string;
  whatsapp: string;
  gender: string;
  maritalStatus: string;
  age: string;
  bloodGroup: string;
  weight: string;
  profileImage?: { url: string };
};

const defaultFormData: UserFormData = {
  name: '',
  phone: '',
  whatsapp: '',
  gender: '',
  maritalStatus: '',
  age: '',
  bloodGroup: '',
  weight: '',
};

export default function UserSettings() {
  const queryClient = useQueryClient();
  const [formData, setFormData] = useState<UserFormData>(defaultFormData);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const { data: profile, isLoading } = useQueryWrapper<UserProfile>(
    ['user-profile'],
    '/user/get-my-profile',
    { withToken: true, withCredentials: true }
  );

  const uploadImage = async (file: File): Promise<{ url: string; key: string }> => {
    const formDataUpload = new FormData();
    formDataUpload.append('file', file);
    const [response, error] = await PostRequestAxios<ImageUploadResponse>(
      '/image/upload',
      formDataUpload,
      { withToken: true, withCredentials: true, headers: { 'Content-Type': 'multipart/form-data' } }
    );
    if (error || !response) throw new Error(error?.message || 'Failed to upload image');
    return response.data;
  };

  const updateProfile = async (data: UserFormData & { profileImage?: { url: string } }) => {
    const payload: Record<string, unknown> = {
      name: data.name,
      phone: data.phone || undefined,
      whatsapp: data.whatsapp || undefined,
      gender: data.gender || undefined,
      maritalStatus: data.maritalStatus || undefined,
      age: data.age ? parseInt(data.age, 10) : undefined,
      bloodGroup: data.bloodGroup || undefined,
      weight: data.weight ? parseInt(data.weight, 10) : undefined,
    };
    if (data.profileImage?.url) {
      payload.profileImage = data.profileImage;
    }
    const [response, error] = await PatchRequestAxios<UserProfile>(
      '/user/update-profile',
      payload,
      { withToken: true, withCredentials: true }
    );
    if (error || !response) throw new Error(error?.message || 'Failed to update profile');
    return response;
  };

  const updateMutation = useMutation({
    mutationFn: async (data: UserFormData) => {
      setIsSubmitting(true);
      let profileImageUrl = profile?.profileImage?.url;
      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        profileImageUrl = uploaded.url;
      }
      return updateProfile({ ...data, profileImage: profileImageUrl ? { url: profileImageUrl } : undefined });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-profile'] });
      toast.success('Profile updated successfully');
      setImageFile(null);
    },
    onError: (error: any) => {
      toast.error(error?.message || 'Failed to update profile');
    },
    onSettled: () => {
      setIsSubmitting(false);
    },
  });

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setImageFile(file);
      const reader = new FileReader();
      reader.onloadend = () => setImagePreview(reader.result as string);
      reader.readAsDataURL(file);
    }
  };

  const handleRemoveImage = () => {
    setImageFile(null);
    setImagePreview(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const currentImage = imagePreview || profile?.profileImage?.url;

  if (isLoading) {
    return (
      <UserLayout>
        <div className="flex h-64 items-center justify-center">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      </UserLayout>
    );
  }

  if (profile && formData.name === '') {
    setFormData({
      name: profile.name || '',
      phone: profile.phone || '',
      whatsapp: profile.whatsapp || '',
      gender: profile.gender || '',
      maritalStatus: profile.maritalStatus || '',
      age: profile.age?.toString() || '',
      bloodGroup: profile.bloodGroup || '',
      weight: profile.weight?.toString() || '',
    });
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateMutation.mutate(formData);
  };

  const handleChange = (field: keyof UserFormData, value: string) => {
    setFormData((prev) => ({ ...prev, [field]: value }));
  };

  return (
    <UserLayout>
      <div className="space-y-6 max-w-3xl mx-auto">
        <div>
          <h1 className="text-2xl font-bold">Settings</h1>
          <p className="text-muted-foreground">Manage your account settings and profile information.</p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Credits</CardTitle>
            <CardDescription>Current available credits in your account.</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{profile?.credits || 0}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Profile Information</CardTitle>
            <CardDescription>Update your personal details and profile picture.</CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-6">
              <div className="flex flex-col items-center gap-4">
                <div className="relative">
                  {currentImage ? (
                    <div className="relative w-32 h-32 rounded-full overflow-hidden border-4 border-muted">
                      <img src={currentImage} alt="Profile" className="w-full h-full object-cover" />
                      <Button
                        type="button"
                        variant="destructive"
                        size="icon"
                        className="absolute top-0 right-0 h-6 w-6 rounded-full"
                        onClick={handleRemoveImage}
                      >
                        <X className="h-3 w-3" />
                      </Button>
                    </div>
                  ) : (
                    <div
                      className="w-32 h-32 rounded-full bg-muted flex items-center justify-center cursor-pointer hover:bg-muted/80 transition-colors border-4 border-dashed border-muted-foreground/50"
                      onClick={() => fileInputRef.current?.click()}
                    >
                      <Upload className="h-8 w-8 text-muted-foreground" />
                    </div>
                  )}
                </div>
                <input
                  type="file"
                  ref={fileInputRef}
                  className="hidden"
                  accept="image/*"
                  onChange={handleImageSelect}
                />
                <p className="text-sm text-muted-foreground">Click to upload profile picture</p>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="name">Full Name *</Label>
                  <Input
                    id="name"
                    value={formData.name}
                    onChange={(e) => handleChange('name', e.target.value)}
                    placeholder="Enter your full name"
                    required
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="phone">Phone Number</Label>
                  <Input
                    id="phone"
                    value={formData.phone}
                    onChange={(e) => handleChange('phone', e.target.value)}
                    placeholder="Enter phone number"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="whatsapp">WhatsApp Number</Label>
                  <Input
                    id="whatsapp"
                    value={formData.whatsapp}
                    onChange={(e) => handleChange('whatsapp', e.target.value)}
                    placeholder="Enter WhatsApp number"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="age">Age</Label>
                  <Input
                    id="age"
                    type="number"
                    min="10"
                    max="100"
                    value={formData.age}
                    onChange={(e) => handleChange('age', e.target.value)}
                    placeholder="Enter age"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="gender">Gender</Label>
                  <Select
                    value={formData.gender}
                    onValueChange={(value) => handleChange('gender', value)}
                  >
                    <SelectTrigger id="gender">
                      <SelectValue placeholder="Select gender" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Male">Male</SelectItem>
                      <SelectItem value="Female">Female</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="maritalStatus">Marital Status</Label>
                  <Select
                    value={formData.maritalStatus}
                    onValueChange={(value) => handleChange('maritalStatus', value)}
                  >
                    <SelectTrigger id="maritalStatus">
                      <SelectValue placeholder="Select status" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Never Married">Never Married</SelectItem>
                      <SelectItem value="Divorced">Divorced</SelectItem>
                      <SelectItem value="Widowed">Widowed</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="bloodGroup">Blood Group</Label>
                  <Select
                    value={formData.bloodGroup}
                    onValueChange={(value) => handleChange('bloodGroup', value)}
                  >
                    <SelectTrigger id="bloodGroup">
                      <SelectValue placeholder="Select blood group" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="A+">A+</SelectItem>
                      <SelectItem value="A-">A-</SelectItem>
                      <SelectItem value="B+">B+</SelectItem>
                      <SelectItem value="B-">B-</SelectItem>
                      <SelectItem value="AB+">AB+</SelectItem>
                      <SelectItem value="AB-">AB-</SelectItem>
                      <SelectItem value="O+">O+</SelectItem>
                      <SelectItem value="O-">O-</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="weight">Weight (kg)</Label>
                  <Input
                    id="weight"
                    type="number"
                    min="20"
                    max="200"
                    value={formData.weight}
                    onChange={(e) => handleChange('weight', e.target.value)}
                    placeholder="Enter weight in kg"
                  />
                </div>
              </div>

              <div className="flex justify-end">
                <Button type="submit" disabled={isSubmitting || !formData.name}>
                  {isSubmitting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  <Save className="mr-2 h-4 w-4" />
                  Save Changes
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </div>
    </UserLayout>
  );
}
